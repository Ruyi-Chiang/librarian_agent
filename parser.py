
from langchain.tools import Tool
import requests
from bs4 import BeautifulSoup
import os

from dotenv import load_dotenv
# Load environment variables
load_dotenv()

# Configure OpenAI API
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

def get_call_number(title: str) -> str:
    search_url = f"https://sunnyvale.bibliocommons.com/v2/search?query={title.replace(' ', '+')}"
    r = requests.get(search_url)
    soup = BeautifulSoup(r.text, 'html.parser')
    
    # Modify this line based on actual HTML structure
    call_number = soup.select_one(".call-number").text.strip()
    return call_number if call_number else "Call number not found."

library_tool = Tool(
    name="LibraryCallNumberSearch",
    func=get_call_number,
    description="Use this to find the call number of a book at the library using its title."
)

from langchain.agents import initialize_agent
from langchain_community.llms import OpenAI

llm = OpenAI(temperature=0)

agent = initialize_agent(
    tools=[library_tool],
    llm=llm,
    agent="zero-shot-react-description",
    verbose=True
)

# Run the agent
agent.run("What's the call number for 'Learning how to learn'?")
# Y 370.1523 OAK
agent.run("What's the call number for 'the mom test'?")
# The Mom Test isn't available at the library but the agent found the closest match and returned the call number:170.44 R, which is wrong.