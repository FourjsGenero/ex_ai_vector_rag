# AI RAG demo using VECTOR types

## Description

This demo uses VECTOR data types in SQL databases, to do similarity search on text chunks,
it order to feed an LLMs with better context and get accurate responses.

## Disclaimer

THIS SOURCE CODE IS PROVIDED "AS IS" AND "WITH ALL FAULTS." FOURJS AND THE AUTHORS MAKE NO
GUARANTEES OR WARRANTIES OF ANY KIND CONCERNING THE SAFETY, RELIABILITY, OR SUITABILITY OF
THE SOFTWARE FOR ANY MAIN OR PARTICULAR PURPOSE.

IN NO EVENT SHALL FOURJS, THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT
OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

THIS DEMO SHOWS HOW TO IMPLEMENT RAG IN A GENERO APPLICATION, AND REQUIRES A THIRD-PARTY AI
PROVIDER, A COMPATIBLE LARGE LANGUAGE MODEL (LLM), AND A VALID API KEY. USERS ARE SOLELY
RESPONSIBLE FOR ANY COSTS, USAGE LIMITS, AND TERMS OF SERVICE ASSOCIATED WITH THEIR CHOSEN
AI PROVIDER.

USING THIS SOFTWARE INVOLVES TRANSMITTING DATA TO THIRD-PARTY SERVICES. BEFORE PROCEEDING,
YOU MUST EVALUATE THE SECURITY, PRIVACY, AND CONFIDENTIALITY IMPLICATIONS OF SHARING SENSITIVE
INFORMATION WITH THESE PROVIDERS. THE AUTHORS ARE NOT LIABLE FOR ANY DATA BREACHES OR MISUSE
OF INFORMATION BY THIRD-PARTY AI ENTITIES.

## Supported AI providers and services

Supported AI Providers:
- Anthropic/Claude
- OpenAI/GPT
- Google/Gemini
- Mistral

## License

This source code is under [MIT license](./LICENSE)

## Prerequisites

* Latest Genero version
* GNU Make
* FGL AI API SDK from `fgl_ai_sdk` repository
* SQL database versions and requirements:
  - PostgreSQL: Install pgvector/pgvectorscale extensions
  - Oracle DB: Must be Oracle 26ai with VECTOR type support
  - SQL Server: Must be SQL Server 2025 with VECTOR type support
* SQL Database client corresponding to the server

## Setup

This demo uses modules from the `fgl_ai_sdk` repository. You must first clone
this repository, compile the AI SDK modules and set the FGLLDPATH environment
variable to point to your local copy of `fgl_ai_sdk`.

You may want to git clone the `fgl_ai_sdk` as sibling directory to your clone
of this current repository, and then set FGLLDPATH as follows:
```bash
$ export FGLLDPATH="../fgl_ai_sdk"
```

## Usage

### Register to AI provider

In order to have access to an AI provider API, register and get an API Key.

**WARNING**: API Keys need to be be kept secret.

- Anthropic/Claude:
  - https://platform.claude.com/docs/en/get-started
  - Voyage AI for embeddings: https://dashboard.voyageai.com/organization/projects
- OpenAI/GPT:
  - https://developers.openai.com/api/docs/quickstart
- Google/Gemini:
  - https://ai.google.dev/gemini-api/docs/quickstart
- Mistral:
  - https://docs.mistral.ai/getting-started/quickstart

Define the following environment variables, according to the AI provider:

- Anthropic/Claude:
  - ANTHROPIC_API_KEY: The API Key
  - VOYAGE_API_KEY: The API Key for embeddings
- OpenAI/GPT:
  - OPENAI_API_KEY: The API Key
- Google/Gemini:
  - GOOGLE_PROJECT_ID: The Google project ID
  - GEMINI_API_KEY: The API Key
- Mistral:
  - MISTRAL_API_KEY: The API Key

### Compilation

```bash
make clean all
```

### Check/Setup DB client env

Ensure you have database client settings (LD_LIBRARY_PATH, data source, locale settings)
properly defined to access your test database.

### Starting the demo

After compilation, run the main program to start the demo:
```bash
$ export ANTHROPIC_API_KEY="sk-ant-..."
$ export VOYAGE_API_KEY="pa-b..."

$ fglrun ai_rag_quotes.42m "anthropic" "clause-opus-4-6" "items_1.json" "mydbsrc" myuser mypswd
```

### Using the demo program

#### Initialization

1) Select the AI provider and text completion model
2) Define the vector dimension (default is OK)
3) Initialize the test table with the `[1. Init SQL table]` button
4) Fill the items list with the `[2. Load item list]` button
5) Compute vectors for each row with `[3. Compute embeddings]` button

#### Detailed RAG procedure

1) Open the `2-step query` folder page
2) In the first field, enter item search criteria like "Sports items"
3) Compute the search vector with the `[Compute context vector]` button
4) Run the SQL query with the `[Find matching rows]` button
5) If too few or tto many items are found, adjust the MAX cosine similarity ratio
6) Enter the user question in the last field
7) Ask the LLM with the `[Send request to LLM]` button

#### End-user mode

1) Open the `Direct query` folder page
2) Enter the user question in the first field
3) Ask the LLM with the `[Send request to LLM]` button

In this case, the relevant items are searched in the database by using the user
query as search criteria to compare with stored vectors describing items.

THIS SHOULD BE REFINED BY EXTRACTING CONCEPTS FOUND IN THE USER QUESTION

## TODO:

- Direct query panel:
  For now, we use directly the user question to generate the search vector and find
  the matching items. If this is sufficient to find relevant items, it's a good
  solution.
  Othewise, try the following (needs system prompt instructions review and tool):
  - Ask LLM to extract concepts from user question (there can be several concepts!)
  - Provide a tool to return items descriptions from a concept:
      `get_matching_items(concept)` => json array of items descriptions
  - For each concept found in the user query, ask LLM will callback the tool to
    fetch items descriptions for the concept.
  - Let LLM generate the final answer using the matching items.

- Detach text embedding model from LLM model.

## Bug fixes:
- none
