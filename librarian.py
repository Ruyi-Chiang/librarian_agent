import os
import urllib.parse
from datetime import datetime

import requests
from bs4 import BeautifulSoup
from dotenv import load_dotenv
from langchain_core.messages import AIMessage, SystemMessage
from langchain_core.tools import tool
from langchain_openai import ChatOpenAI
from langgraph.graph import END, START, MessagesState, StateGraph
from langgraph.prebuilt import ToolNode, tools_condition
from requests import Response

# Load environment variables from .env file
load_dotenv()

# Notion Custom Functions
NOTION_TOKEN = os.environ.get("NOTION_TOKEN")
DATABASE_ID = os.environ.get("NOTION_DATABASE_ID")

headers = {
    "Authorization": "Bearer " + NOTION_TOKEN,
    "Content-Type": "application/json",
    "Notion-Version": "2022-06-28",
}


def create_notion_page(data: dict) -> Response:
    """
    Insert a new entry to a Notion database called Book Tracker when given a dictionary with book title, status, call number, library location and updated date.
    """
    create_url = "https://api.notion.com/v1/pages"

    payload = {"parent": {"database_id": DATABASE_ID}, "properties": data}

    # Debug: Print payload
    print("Payload:", payload)
    print("Headers:", headers)

    res = requests.post(create_url, headers=headers, json=payload)
    # print(res.status_code)
    # Debug: Print response details
    print(f"Status: {res.status_code}")
    print(f"Response: {res.text}")

    if res.status_code != 200:
        print(f"Error: {res.status_code} - {res.text}")
    return res


@tool
def write_to_notion(
    book_title: str,
    call_number: str,
    status: str,
    location: str = "Sunnyvale Public Library",
    date_str: str = None,
) -> str:
    """
    Write book information to Notion database.

    Args:
        book_title: The title of the book
        call_number: The library call number
        location: The name of the library
        date_str: The date call the function on
        status: The availability status, must be among "Available now", "Not Available", "All copies in use".

    Returns:
        A message confirming the data was written to Notion
    """
    try:
        if date_str is None:
            date_str = datetime.now().strftime("%Y-%m-%d")

        notion_data = {
            "Title": {"title": [{"text": {"content": book_title}}]},
            "Status": {
                "status": {
                    "name": status
                }  # must match an existing Status option in Notion
            },
            "Call Number": {"rich_text": [{"text": {"content": call_number}}]},
            "Library Location": {"rich_text": [{"text": {"content": location}}]},
            "Date": {"date": {"start": date_str, "end": None}},
        }
        # Call the Notion API
        response = create_notion_page(notion_data)

        if response.status_code == 200:
            return f"Successfully added '{book_title}' to Notion database. Call number: {call_number}, Status: {status}"
        else:
            return f"Failed to add to Notion. Status: {response.status_code}, Response: {response.text}"

    except Exception as e:
        return f"Error writing to Notion: {str(e)}"


# Custom Tools for library catalog searching
def search_library_page(query: str) -> str:
    """
    Searches the Sunnyvale library catalog using smart search and returns visible text from the top search results.

    The smart search can handle various types of queries including:
    - Book titles (e.g., "The Great Gatsby", "Never Search Alone")
    - Author names (e.g., "Adam Grant", "F. Scott Fitzgerald" or "Fitzgerald")
    - Keywords or subjects (e.g., "mystery", "science fiction", "cooking")
    - Partial titles or phrases

    Args:
        query: Search term that can be a title, author name, keyword, or any other searchable text

    Returns:
        str: Visible text from up to 3 search result cards, or error message if search fails
    """
    encoded_query = urllib.parse.quote(query)
    search_url = f"https://sunnyvale.bibliocommons.com/v2/search?query={encoded_query}&searchType=smart"
    response = requests.get(search_url)

    if response.status_code != 200:
        return "Failed to fetch search results."

    soup = BeautifulSoup(response.text, "html.parser")

    # Extract text from multiple result cards (up to 3 results)
    result_cards = soup.find_all("li", class_="cp-search-result-item", limit=3)

    if not result_cards:
        return "No search results found."

    # Combine text from all found result cards
    all_results = []
    for i, card in enumerate(result_cards, 1):
        card_text = card.get_text(separator="\n", strip=True)
        all_results.append(f"--- Result {i} ---\n{card_text}")

    return "\n\n".join(all_results)


# Worker Agent Setup -- Initialize LLM with tools
llm = ChatOpenAI(model="gpt-4o")
llm_with_tools = llm.bind_tools([search_library_page, write_to_notion])


# Node function
def tool_calling_llm(state: MessagesState):
    input_messages = [
        SystemMessage(
            content="""You are a librarian specializing in searching the library catalog.
            - Your main tasks: search for books and record results in the Notion database.
            - Always detect and prioritize catalog queries, even if hidden inside greetings or casual conversation.
            - Only accept catalog-related queries. For anything else, politely refuse as out of scope and redirect the user back to catalog search.
            - Refusal template: “I only handle catalog searches—please ask about a book.
            - Allowed book statuses: “Available now”, “Not available”, “All copies in use”.
            - After successfully writing a result to Notion, stop."""
        )
    ]

    return {"messages": [llm_with_tools.invoke(input_messages + state["messages"])]}


# TODO: Research how to initialize a conversation in LangGraph
# https://github.com/langchain-ai/langgraph/discussions/919
initial_state = {
    "messages": [
        AIMessage(
            "Hi, I'm your AI librarian searching catalog for Sunnyvale Public Library. What book title are you looking for today?"
        )
    ]
}
# Build graph
builder = StateGraph(MessagesState)
builder.add_node("tool_calling_llm", tool_calling_llm)
builder.add_node("tools", ToolNode([search_library_page, write_to_notion]))
builder.add_edge(START, "tool_calling_llm")
builder.add_conditional_edges(
    "tool_calling_llm",
    # If the latest message (result) from assistant is a tool call -> tools_condition routes to tools
    # If the latest message (result) from assistant is a not a tool call -> tools_condition routes to END
    tools_condition,
)
builder.add_edge("tools", "tool_calling_llm")
builder.add_edge("tools", END)

graph = builder.compile()
