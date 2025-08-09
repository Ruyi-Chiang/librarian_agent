import os
from dotenv import load_dotenv
from langchain_openai import ChatOpenAI
from langchain_core.messages import HumanMessage
from langgraph.graph import StateGraph, START, END
from langgraph.graph import MessagesState
from langgraph.prebuilt import ToolNode, tools_condition


# Load environment variables from .env file
load_dotenv()

import urllib.parse

import requests
from bs4 import BeautifulSoup

title = "maybe you should talk to someone"
encoded_title = urllib.parse.quote(title)

def search_library_page(title: str) -> str:
    """
    Searches the Sunnyvale library and returns visible text from the top search result for the LLM to interpret.
    """
    encoded_title = urllib.parse.quote(title)
    search_url = f"https://sunnyvale.bibliocommons.com/v2/search?query={encoded_title}&searchType=smart"
    response = requests.get(search_url)

    if response.status_code != 200:
        return "Failed to fetch search results."

    soup = BeautifulSoup(response.text, "html.parser")

    # Extract text from the first result card
    result_card = soup.find("li", class_="cp-search-result-item")
    if not result_card:
        return "No search result found."

    # Get all visible text inside the result card
    return result_card.get_text(separator="\n", strip=True)

def multiply(a: int, b: int) -> int:
    """Multiply a and b.

    Args:
        a: first int
        b: second int
    """
    return a * b

# Initialize LLM with tools
llm = ChatOpenAI(model="gpt-4o")
llm_with_tools = llm.bind_tools([multiply, search_library_page])

# Node function
def tool_calling_llm(state: MessagesState):
    return {"messages": [llm_with_tools.invoke(state["messages"])]}

# Build graph
builder = StateGraph(MessagesState)
builder.add_node("tool_calling_llm", tool_calling_llm)
builder.add_node("tools", ToolNode([multiply, search_library_page]))
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