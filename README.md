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

THIS SDK IS A CONNECTOR AND REQUIRES A THIRD-PARTY AI PROVIDER, A COMPATIBLE LARGE LANGUAGE
MODEL (LLM), AND A VALID API KEY. USERS ARE SOLELY RESPONSIBLE FOR ANY COSTS, USAGE LIMITS,
AND TERMS OF SERVICE ASSOCIATED WITH THEIR CHOSEN AI PROVIDER.

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

### Starting the demo

After compilation, run the main program to start the demo:
```bash
$ export ANTHROPIC_API_KEY="sk-ant-..."
$ export VOYAGE_API_KEY="pa-b..."

$ fglrun ai_rag_quotes.42m "anthropic" "clause-opus-4-6" "mydbsrc" myuser mypswd
```

## TODO:
- Save current settings (provider, model) to env file.
- Detach text embedding model from LLM model.

## Bug fixes:
- none
