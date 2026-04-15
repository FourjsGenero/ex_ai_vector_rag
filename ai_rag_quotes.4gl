IMPORT FGL aim_anthropic
IMPORT FGL aim_openai
IMPORT FGL aim_gemini
IMPORT FGL aim_mistral
IMPORT FGL aim_vectors

CONSTANT c_vector_dimension INTEGER = 1024

TYPE t_famquote RECORD
       pkey INT,
       author STRING,
       language STRING,
       quote STRING,
       emb TEXT
     END RECORD

TYPE t_famquote_attr RECORD
       pkey STRING,
       author STRING,
       language STRING,
       quote STRING,
       emb STRING
     END RECORD

TYPE t_context_item RECORD
       pkey INT,
       data STRING
     END RECORD

CONSTANT c_rag_info_delimiter STRING = "```"

DEFINE provider STRING

MAIN
    DEFINE x, s INTEGER
    DEFINE dbsource, dbuser, dbpswd, dbserver STRING
    DEFINE quote_list DYNAMIC ARRAY OF t_famquote
    DEFINE quote_list_attr DYNAMIC ARRAY OF t_famquote_attr
    DEFINE search_context STRING = "Famous quotes related to political concerns"
    DEFINE min_cosine_similarity FLOAT = 0.30
    DEFINE search_vector STRING
    DEFINE assistant_message STRING
    DEFINE system_message STRING = "You are a history professor.
 You can answer questions about quotes made by famous people or movie characters.
 Generate your answer using the relevant quotes provided in the assistant message.
 Always mention the famous quote and the author of the quote in your answer."
    DEFINE context_items DYNAMIC ARRAY OF t_context_item
    DEFINE user_question STRING = "Who is known for a famous quote about racism?"
    DEFINE llm_response STRING

    OPEN FORM f1 FROM "ai_rag_quotes"
    DISPLAY FORM f1

    LET provider = NVL(arg_val(1),"anthropic")
    LET dbsource = NVL(arg_val(2),"test1+driver='dbmpgs_9'")
    LET dbuser =  NVL(arg_val(3),"pgsuser")
    LET dbpswd =  NVL(arg_val(4),"fourjs")

    IF dbuser IS NULL THEN
        CONNECT TO dbsource USER dbuser USING dbpswd
    ELSE
        CONNECT TO dbsource USER dbuser USING dbpswd
    END IF
    LET dbserver = fgl_db_driver_type()

    -- Init all AI SDK modules: User can choose provider later on...
    CALL aim_anthropic.initialize()
    CALL aim_openai.initialize()
    CALL aim_gemini.initialize()
    CALL aim_mistral.initialize()

    -- Init embeddings SDK
    CALL aim_mistral.initialize()

    LET s = fill_quote_list(quote_list)

    DIALOG ATTRIBUTES(UNBUFFERED)

        DISPLAY ARRAY quote_list TO sr_quote_list.*
        END DISPLAY

        INPUT BY NAME dbserver, dbsource, provider, system_message,
                      search_context, min_cosine_similarity, search_vector,
                      assistant_message, user_question,
                      llm_response
            ATTRIBUTES(WITHOUT DEFAULTS)

            ON CHANGE provider
               UPDATE famquote SET emb = NULL
               LET s = fill_quote_list(quote_list)
               CALL quote_list_attr.clear()

        END INPUT

        BEFORE DIALOG
           CALL DIALOG.setArrayAttributes("sr_quote_list",quote_list_attr)

        ON ACTION init_sql_table
           CALL init_sql_table()
           CALL quote_list.clear()
           CALL quote_list_attr.clear()
           LET assistant_message = NULL
           LET llm_response = NULL

        ON ACTION fill_quote_list
           LET s = fill_quote_list(quote_list)
           CALL quote_list_attr.clear()
           LET assistant_message = NULL
           LET llm_response = NULL

        ON ACTION compute_vector_embeddings
           CALL compute_vector_embeddings(provider)
           LET s = fill_quote_list(quote_list)
           CALL quote_list_attr.clear()
           LET assistant_message = NULL
           LET llm_response = NULL

        ON ACTION search_vector
           LET assistant_message = NULL
           LET llm_response = NULL
           LET search_vector = compute_search_vector(provider,search_context)
           IF search_vector IS NULL THEN
               CALL _mbox_ok("Could not compute search vector.")
           END IF

        ON ACTION find_match
           LET llm_response = NULL
           IF search_vector IS NULL THEN
               CALL _mbox_ok("First you need to compute the search vector from context sentence.")
               CONTINUE DIALOG
           END IF
           LET x = find_matching_quotes(min_cosine_similarity,search_vector,context_items)
           IF x == 0 THEN
               LET assistant_message = NULL
               CALL _mbox_ok("No matching quotes found in database!\nChange min cosine similarity.")
           ELSE
               LET assistant_message = build_assistant_message(search_context,context_items)
               CALL fill_quote_list_attrs(quote_list,context_items,quote_list_attr)
               CALL _mbox_ok(SFMT("Found %1 matching quotes in database!",x))
           END IF

        ON ACTION ask_llm
           LET llm_response = send_question_to_llm(provider,system_message,assistant_message,user_question)

        ON ACTION close
           EXIT DIALOG

    END DIALOG

    CALL aim_anthropic.cleanup()
    CALL aim_openai.cleanup()
    CALL aim_gemini.cleanup()
    CALL aim_mistral.cleanup()

END MAIN

FUNCTION init_sql_table() RETURNS ()

    DEFINE x INTEGER
    DEFINE sqlcmd STRING
    DEFINE arr DYNAMIC ARRAY OF t_famquote =
    [
     (
      pkey: 101, author: "Martin Luther Kind Jr", language: "English",
      quote: "I have a dream that my four little children will one day live in a nation where they will not be judged by the color of their skin but by the content of their character."
     )
     ,(
      pkey: 102, author: "Winston Churchill", language: "English",
      quote: "If you are going through hell, keep going."
     )
     ,(
      pkey: 103, author: "Neil Amstrong", language: "English",
      quote: "That’s one small step for man, one giant leap for mankind."
     )
     ,(
      pkey: 104, author: "Abraham Lincoln", language: "English",
      quote: "You can fool all of the people some of the time, and some of the people all of the time, but you can't fool all of the people all of the time."
     )
     ,(
      pkey: 105, author: "Robert Frost", language: "English",
      quote: "Two roads diverged in a wood, and I, I took the one less travelled by, and that has made all the difference."
     )
     ,(
      pkey: 106, author: "John Kennedy", language: "English",
      quote: "Ask not what your country can do for you; ask what you can do for your country."
     )
     ,(
      pkey: 107, author: "Forrest Gump (movie character)", language: "English",
      quote: "Life is like a box of chocolates. You never know what you’re gonna get."
     )
     ,(
      pkey: 108, author: "Hubert Bonisseur de La Bath (movie character)", language: "French",
      quote: "À l'occasion, je vous mettrai un petit coup de polish."
     )
     ,(
      pkey: 109, author: "Antoine de Saint-Exupéry", language: "French",
      quote: "On ne voit bien qu'avec le cœur. L'essentiel est invisible pour les yeux."
     )
     ,(
      pkey: 110, author: "Edmond Rostand", language: "French",
      quote: "Il y a beaucoup de gens dont la facilité de parler ne vient que de l'impuissance de se taire."
     )
     ,(
      pkey: 111, author: "Obi-Wan Kenobi (movie character)", language: "English",
      quote: "May the Force be with you!"
     )
     ,(
      pkey: 112, author: "Otis (movie character)", language: "French",
      quote: "Vous savez, moi je ne crois pas qu'il y ait de bonne ou de mauvaise situation.
 Moi, si je devais résumer ma vie aujourd'hui avec vous, je dirais que c'est d'abord des rencontres."
     )
     ,(
      pkey: 113, author: "Albert Einstein", language: "English",
      quote: "A person who never made a mistake never tried anything new."
     )
     ,(
      pkey: 114, author: "Benjamin Franklin", language: "English",
      quote: "Tell me and I forget. Teach me and I remember. Involve me and I learn."
     )
    ]

    WHENEVER ERROR CONTINUE
    DROP TABLE famquote
    WHENEVER ERROR STOP
    LET sqlcmd = "CREATE TABLE famquote ("
                  || " pkey INT, author VARCHAR(50), language VARCHAR(50), quote VARCHAR(2000)"
                  || SFMT(", emb %1", _vector_sql_data_type(c_vector_dimension) )
                  || ")"
display "SQL: ", sqlcmd
    EXECUTE IMMEDIATE sqlcmd

    -- First insert rows without embeddings
    PREPARE stmt1 FROM "INSERT INTO famquote VALUES (?,?,?,?,NULL)"
    FOR x = 1 TO arr.getLength()
        EXECUTE stmt1 USING arr[x].pkey, arr[x].author, arr[x].language, arr[x].quote
    END FOR

END FUNCTION

-- Table may not yet exist.
FUNCTION fill_quote_list(
    arr DYNAMIC ARRAY OF t_famquote
) RETURNS INTEGER
    DEFINE x INTEGER
    DEFINE sqlcmd STRING

    TRY
        SELECT COUNT(*) INTO x FROM famquote
    CATCH
        RETURN -1
    END TRY

    LET sqlcmd = "SELECT pkey, author, language, quote"
                  || SFMT(", %1", _vector_sql_fetch_expr("emb",c_vector_dimension))
                  || " FROM famquote ORDER BY pkey"
display "SQL:", sqlcmd
    DECLARE c_fill_quote_list CURSOR FROM sqlcmd
    CALL arr.clear()
    OPEN c_fill_quote_list
    LET x = 1
    WHILE sqlca.sqlcode == 0
        LOCATE arr[x].emb IN FILE
        FETCH c_fill_quote_list INTO arr[x].*
        IF sqlca.sqlcode == NOTFOUND THEN
            EXIT WHILE
        END IF
        LET x = x+1
    END WHILE
    CALL arr.deleteElement(x)

    RETURN arr.getLength()

END FUNCTION

FUNCTION fill_quote_list_attrs(
    quote_list DYNAMIC ARRAY OF t_famquote,
    context_items DYNAMIC ARRAY OF t_context_item,
    quote_list_attr DYNAMIC ARRAY OF t_famquote_attr
) RETURNS ()

    DEFINE x, n INTEGER

    CALL quote_list_attr.clear()
    FOR x = 1 TO context_items.getLength()
        LET n = quote_list.search("pkey",context_items[x].pkey)
        IF n>0 THEN
            --LET quote_list_attr[n].quote = "green reverse"
            LET quote_list_attr[n].quote = "green bold"
        END IF
    END FOR

END FUNCTION

FUNCTION _init_vector_embedding_request(
    provider STRING,
    te_client aim_vectors.t_client INOUT,
    te_request aim_vectors.t_text_embedding_request INOUT
) RETURNS ()
    CASE provider
    WHEN "anthropic" -- Must use VoyageAI for vector generation!
        CALL te_client.set_defaults("voyageai","voyage-3-large")
        CALL te_request.set_defaults(te_client,NULL)
    WHEN "openai"
        CALL te_client.set_defaults("openai","text-embedding-3-small")
        CALL te_request.set_defaults(te_client,c_vector_dimension)
    WHEN "mistral"
        CALL te_client.set_defaults("mistral","mistral-embed")
        CALL te_request.set_defaults(te_client,NULL) -- dim is always 1024 with mistral
    WHEN "gemini"
        CALL te_client.set_defaults("gemini","gemini-embedding-001")
        CALL te_request.set_defaults(te_client,c_vector_dimension)
    OTHERWISE
        DISPLAY "Unexpected AI provider: ", provider
        EXIT PROGRAM 1
    END CASE
END FUNCTION

FUNCTION compute_vector_embeddings(
    provider STRING
) RETURNS ()

    DEFINE s, x, tt INTEGER
    DEFINE rec t_famquote
    DEFINE source STRING
    DEFINE vector STRING
    DEFINE sqlcmd STRING
    DEFINE te_client aim_vectors.t_client
    DEFINE te_request aim_vectors.t_text_embedding_request
    DEFINE te_response aim_vectors.t_text_embedding_response

    CALL _init_vector_embedding_request(provider,te_client,te_request)

    SELECT COUNT(*) INTO tt FROM famquote

    LET sqlcmd = SFMT("UPDATE famquote SET emb = %1 WHERE pkey = ?", _vector_sql_placeholder(c_vector_dimension))
--display "SQL:", sqlcmd
    PREPARE stmt2 FROM sqlcmd
    DECLARE c_compute_vectors CURSOR FROM "SELECT pkey, author, language, quote FROM famquote WHERE emb IS NULL ORDER BY pkey"
    FOREACH c_compute_vectors INTO rec.*
        LET source = rec.author, " said: ", c_rag_info_delimiter, rec.quote, c_rag_info_delimiter
        LET x = x + 1
        MESSAGE SFMT("Computing vector: %1/%2", x, tt); CALL ui.Interface.refresh()
        CALL te_request.set_source(source)
        LET s = te_client.send_text_embedding_request(te_request,te_response)
        IF s < 0 THEN
            CALL _mbox_ok(SFMT("ERROR: Could not get text embedding from %1.\n Probably HTTP 429? Try again.",provider))
            EXIT FOREACH
        END IF
        LET vector = te_response.get_vector()
--display "vector = ", vector
        EXECUTE stmt2 USING vector, rec.pkey
    END FOREACH

    MESSAGE ""

END FUNCTION

FUNCTION compute_search_vector(
    provider STRING,
    source STRING
) RETURNS STRING

    DEFINE vector STRING
    DEFINE s INTEGER
    DEFINE te_client aim_vectors.t_client
    DEFINE te_request aim_vectors.t_text_embedding_request
    DEFINE te_response aim_vectors.t_text_embedding_response

    CALL _init_vector_embedding_request(provider,te_client,te_request)

    MESSAGE "Waiting for answer..."; CALL ui.Interface.refresh()

    CALL te_request.set_source(source)
    LET s = te_client.send_text_embedding_request(te_request,te_response)
    IF s < 0 THEN
        CALL _mbox_ok(SFMT("ERROR: Could not get text embedding from %1.\n",provider))
        LET vector = NULL
    ELSE
        LET vector = te_response.get_vector()
    END IF

--display "Source text    = ", source
--display "Context vector = ", vector

    MESSAGE ""

    RETURN vector

END FUNCTION

FUNCTION find_matching_quotes(
    min_cosine_similarity FLOAT,
    search_vector STRING,
    context_items DYNAMIC ARRAY OF t_context_item
) RETURNS INTEGER

    DEFINE x INTEGER
    DEFINE sqlcmd STRING
    DEFINE rec t_famquote
    DEFINE cosim FLOAT

    LET sqlcmd = SFMT("SELECT ((1 - (emb <=> %1))) cosim,", _vector_sql_placeholder(c_vector_dimension))
                  || " pkey, author, language, quote FROM famquote"
                  || SFMT(" ORDER BY emb <=> %1", _vector_sql_placeholder(c_vector_dimension))
--display "SQL: ", sqlcmd
    DECLARE c_fetch_related CURSOR FROM sqlcmd
    LET x = 0
    CALL context_items.clear()
    FOREACH c_fetch_related USING search_vector, search_vector INTO cosim, rec.*
display rec.pkey, "  cosine similarity: ", (cosim using "--&.&&&&&&&"), "  min = ", min_cosine_similarity
        IF cosim < min_cosine_similarity THEN EXIT FOREACH END IF
        LET x = x+1
        LET context_items[x].pkey = rec.pkey
        LET context_items[x].data = rec.author, " said: ",
                   c_rag_info_delimiter, rec.quote, c_rag_info_delimiter
    END FOREACH

    RETURN context_items.getLength()

END FUNCTION

FUNCTION _vector_sql_data_type(dimension INTEGER) RETURNS STRING
    CASE fgl_db_driver_type()
    WHEN "ora" RETURN SFMT("VECTOR(%1,FLOAT32)",dimension)
    OTHERWISE  RETURN SFMT("VECTOR(%1)",dimension) -- PostgreSQL
    END CASE
END FUNCTION

FUNCTION _vector_sql_placeholder(dimension INTEGER) RETURNS STRING
    CASE fgl_db_driver_type()
    WHEN "pgs" RETURN SFMT("?::vector(%1)",dimension)
    WHEN "ora" RETURN SFMT("VECTOR(?,%1,FLOAT32)",dimension)
    OTHERWISE  RETURN "?" -- Oracle
    END CASE
END FUNCTION

FUNCTION _vector_sql_fetch_expr(expr STRING, dimension INTEGER) RETURNS STRING
    LET dimension = NULL
    CASE fgl_db_driver_type()
    WHEN "pgs" RETURN SFMT("%1::text",expr)
    WHEN "ora" RETURN expr -- Must be fetched into TEXT !
    OTHERWISE  RETURN expr
    END CASE
END FUNCTION

FUNCTION build_assistant_message(
    search_context STRING,
    context_items DYNAMIC ARRAY OF t_context_item
) RETURNS STRING

    DEFINE x INTEGER
    DEFINE result_set base.StringBuffer

    LET result_set = base.StringBuffer.create()
    CALL result_set.append("Relevant "|| search_context || ":")
    FOR x = 1 TO context_items.getLength()
        CALL result_set.append("\n")
        CALL result_set.append(context_items[x].data)
    END FOR
    RETURN result_set.toString()

END FUNCTION

FUNCTION send_question_to_llm(
    provider STRING,
    system_message STRING,
    assistant_message STRING,
    question STRING
) RETURNS STRING

    DEFINE result STRING
let provider =null
let system_message =null
let assistant_message =null
let question =null
{
    DEFINE s, x INTEGER
    --
    DEFINE oai_client OpenAI.t_client
    DEFINE oai_chat_request OpenAI.t_chat_request
    DEFINE oai_chat_response OpenAI.t_chat_response
    --
    DEFINE gem_client Gemini.t_client
    DEFINE gem_chat_request Gemini.t_chat_request
    DEFINE gem_chat_response Gemini.t_chat_response

    MESSAGE "Waiting for answer..."; CALL ui.Interface.refresh()

    CASE provider
    WHEN "openai"
        CALL oai_client.set_defaults_openai("gpt-4o")
        CALL oai_chat_request.set_defaults(oai_client)
        LET oai_chat_request.temperature = 1.2
    WHEN "mistral"
        CALL oai_client.set_defaults_mistral("mistral-large-latest")
        CALL oai_chat_request.set_defaults(oai_client)
        LET oai_chat_request.temperature = 1.2
    WHEN "anthropic"
        CALL oai_client.set_defaults_anthropic("claude-3-7-sonnet-20250219")
        CALL oai_chat_request.set_defaults(oai_client)
        LET oai_chat_request.temperature = 0.8
    WHEN "gemini"
        CALL gem_client.set_defaults_gemini(Gemini.text_generation_models[1])
        CALL gem_chat_request.set_defaults(gem_client)
        LET gem_chat_request.generationConfig.temperature = 1.2
    END CASE

    IF length(system_message)>0 THEN
        CASE provider
        WHEN "gemini" CALL gem_chat_request.set_system_instruction(system_message)
        OTHERWISE     LET x = oai_chat_request.append_system_message(system_message)
        END CASE
    END IF
    IF length(assistant_message)>0 THEN
        CASE provider
        WHEN "gemini" LET x = gem_chat_request.append_model_content(assistant_message)
        OTHERWISE     LET x = oai_chat_request.append_assistant_message(assistant_message)
        END CASE
    END IF
    CASE provider
    WHEN "gemini"
        LET x = gem_chat_request.append_user_content(c_rag_info_delimiter||question||c_rag_info_delimiter)
        LET s = gem_client.send_chat_completion_request(gem_chat_request,gem_chat_response)
        LET result = gem_chat_response.get_content(1)
    OTHERWISE
        LET x = oai_chat_request.append_user_message(c_rag_info_delimiter||question||c_rag_info_delimiter)
        LET s = oai_client.send_chat_completion_request(oai_chat_request,oai_chat_response)
        LET result = oai_chat_response.get_content(1)
    END CASE
    IF s<0 THEN
        DISPLAY SFMT("ERROR: Failed to ask question to %1",provider)
        EXIT PROGRAM 1
    END IF

    MESSAGE ""

}
    RETURN result

END FUNCTION

PRIVATE FUNCTION _mbox_ok(msg STRING) RETURNS ()
    MENU "RAG sample" ATTRIBUTES(STYLE="dialog",COMMENT=msg)
        COMMAND "Ok" EXIT MENU
    END MENU
END FUNCTION
