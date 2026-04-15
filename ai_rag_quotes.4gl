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

CONSTANT c_quote_delim STRING = "```"

PRIVATE CONSTANT c_ai_provider_gemini = "gemini"
PRIVATE CONSTANT c_ai_provider_anthropic = "anthropic"
PRIVATE CONSTANT c_ai_provider_mistral = "mistral"
PRIVATE CONSTANT c_ai_provider_openai  = "openai"

MAIN
    DEFINE ai_provider STRING
    DEFINE ai_model STRING
    DEFINE x, s INTEGER
    DEFINE dbsource, dbuser, dbpswd, dbserver STRING
    DEFINE quote_list DYNAMIC ARRAY OF t_famquote
    DEFINE quote_list_attr DYNAMIC ARRAY OF t_famquote_attr
    DEFINE search_context STRING = "Quotes about political concerns"
    DEFINE max_cosine_similarity FLOAT = 0.45
    DEFINE search_vector STRING
    DEFINE context_data STRING
    DEFINE system_message STRING = `You are a middle-school teacher.
 You can answer questions about quotes made by famous people or movie characters.
 Generate your answer using the relevant quotes provided between <quotes> XML markers.
 Always mention the famous quote and the author of the quote in your answer.
 If the answer is not in the context, just respond "I don't know".`
    DEFINE context_items DYNAMIC ARRAY OF t_context_item
    DEFINE user_question STRING = "Who is known for a famous quote about racism?"
    DEFINE llm_response STRING

    OPEN FORM f1 FROM "ai_rag_quotes"
    DISPLAY FORM f1

    LET ai_provider = NVL(arg_val(1),"anthropic")
    LET ai_model = NVL(arg_val(2),"clause-opus-4-6")
    LET dbsource = NVL(arg_val(3),"test1+driver='dbmpgs_9'")
    LET dbuser =  NVL(arg_val(4),"pgsuser")
    LET dbpswd =  NVL(arg_val(5),"fourjs")

    IF dbuser IS NULL THEN
        CONNECT TO dbsource USER dbuser USING dbpswd
    ELSE
        CONNECT TO dbsource USER dbuser USING dbpswd
    END IF
    LET dbserver = fgl_db_driver_type()

    CALL aim_anthropic.initialize()
    CALL aim_openai.initialize()
    CALL aim_gemini.initialize()
    CALL aim_mistral.initialize()

    CALL aim_vectors.initialize()

    LET s = fill_quote_list(quote_list)

    DIALOG ATTRIBUTES(UNBUFFERED)

        DISPLAY ARRAY quote_list TO sr_quote_list.*
        END DISPLAY

        INPUT BY NAME dbserver, dbsource, ai_provider, ai_model, system_message,
                      search_context, max_cosine_similarity, search_vector,
                      context_data, user_question,
                      llm_response
            ATTRIBUTES(WITHOUT DEFAULTS)

            ON CHANGE ai_provider
               LET ai_model = _default_model(ai_provider)
               LET search_vector = NULL
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
           LET context_data = NULL
           LET llm_response = NULL

        ON ACTION fill_quote_list
           LET s = fill_quote_list(quote_list)
           CALL quote_list_attr.clear()
           LET context_data = NULL
           LET llm_response = NULL

        ON ACTION compute_vector_embeddings
           CALL compute_vector_embeddings(ai_provider)
           LET s = fill_quote_list(quote_list)
           CALL quote_list_attr.clear()
           LET context_data = NULL
           LET llm_response = NULL

        ON ACTION search_vector
           LET context_data = NULL
           LET llm_response = NULL
           LET search_vector = compute_search_vector(ai_provider,search_context)
           IF search_vector IS NULL THEN
               CALL _mbox_ok("Could not compute search vector.")
           END IF

        ON ACTION find_match
           LET llm_response = NULL
           IF search_vector IS NULL THEN
               CALL _mbox_ok("First you need to compute the search vector from context sentence.")
               CONTINUE DIALOG
           END IF
           LET x = find_matching_quotes(max_cosine_similarity,search_vector,context_items)
           IF x == 0 THEN
               LET context_data = NULL
               CALL _mbox_ok("No matching quotes found in database!\nIncrease MAX cosine similarity.")
           ELSE
               LET context_data = build_context_data(search_context,context_items)
               CALL fill_quote_list_attrs(quote_list,context_items,quote_list_attr)
               CALL _mbox_ok(SFMT("Found %1 matching quotes in database!",x))
           END IF

        ON ACTION ask_llm
           LET llm_response =
               send_question_to_ai(ai_provider, system_message, context_data, user_question)

        ON ACTION close
           EXIT DIALOG

    END DIALOG

    CALL aim_anthropic.cleanup()
    CALL aim_openai.cleanup()
    CALL aim_gemini.cleanup()
    CALL aim_mistral.cleanup()
    CALL aim_vectors.cleanup()

END MAIN

PRIVATE DEFINE _ai_model_list DYNAMIC ARRAY OF RECORD
        provider STRING,
        model STRING
    END RECORD = [

        ( provider: "gemini", model: "gemini-3.1-pro-preview" ),
        ( provider: "gemini", model: "gemini-3-pro-preview" ),
        ( provider: "gemini", model: "gemini-3-flash-preview" ),
        ( provider: "gemini", model: "gemini-2.5-flash" ),

        ( provider: "openai", model: "gpt-5.2" ),
        ( provider: "openai", model: "gpt-5-mini" ),
        ( provider: "openai", model: "gpt-5-nano" ),
        ( provider: "openai", model: "gpt-5-codex" ),
        ( provider: "openai", model: "gpt-4.1" ),

        ( provider: "anthropic", model: "claude-opus-4-6" ),
        ( provider: "anthropic", model: "claude-sonnet-4-6" ),
        ( provider: "anthropic", model: "claude-haiku-4-5" ),

        ( provider: "mistral", model: "mistral-large-latest" ),
        ( provider: "mistral", model: "mistral-medium-latest" ),
        ( provider: "mistral", model: "mistral-small-latest" )

    ]

FUNCTION _default_model(ai_provider STRING) RETURNS STRING
    DEFINE x INTEGER
    LET x = _ai_model_list.search("provider",ai_provider)
    IF x>0 THEN
        RETURN _ai_model_list[x].model
    ELSE
        RETURN NULL
    END IF
END FUNCTION

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
      pkey: 108, author: "Mahatma Gandhi", language: "English",
      quote: "I cried because I had no shoes, then I met a man who had no feet."
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
     ,(
      pkey: 115, author: "Socrate", language: "English",
      quote: "The only true wisdom is in knowing you know nothing."
     )
     ,(
      pkey: 116, author: "Oscar Wilde", language: "English",
      quote: "There is only one thing in the world worse than being talked about, and that is not being talked about."
     )
    ]

    WHENEVER ERROR CONTINUE
    DROP TABLE famquote
    WHENEVER ERROR STOP
    LET sqlcmd = "CREATE TABLE famquote ("
                  || " pkey INT, author VARCHAR(50), language VARCHAR(50), quote VARCHAR(2000)"
                  || SFMT(", emb %1", _vector_sql_data_type(c_vector_dimension) )
                  || ")"
--display "SQL: ", sqlcmd
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
--display "SQL:", sqlcmd
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
    ai_provider STRING,
    --ai_emb_model STRING,
    te_client aim_vectors.t_client INOUT,
    te_request aim_vectors.t_text_embedding_request INOUT
) RETURNS ()
    CASE ai_provider
    WHEN c_ai_provider_anthropic -- Must use VoyageAI for vector generation!
        CALL te_client.set_defaults("voyageai","voyage-3-large")
        CALL te_request.set_defaults(te_client,NULL)
    WHEN c_ai_provider_openai
        CALL te_client.set_defaults(ai_provider,"text-embedding-3-small")
        CALL te_request.set_defaults(te_client,c_vector_dimension)
    WHEN c_ai_provider_mistral
        CALL te_client.set_defaults(ai_provider,"mistral-embed")
        CALL te_request.set_defaults(te_client,NULL) -- dim is always 1024 with mistral
    WHEN c_ai_provider_gemini
        CALL te_client.set_defaults(ai_provider,"gemini-embedding-001")
        CALL te_request.set_defaults(te_client,c_vector_dimension)
    OTHERWISE
        DISPLAY "Unexpected AI provider: ", ai_provider
        EXIT PROGRAM 1
    END CASE
END FUNCTION

FUNCTION compute_vector_embeddings(
    ai_provider STRING
) RETURNS ()

    DEFINE s, x, tt INTEGER
    DEFINE rec t_famquote
    DEFINE source STRING
    DEFINE vector STRING
    DEFINE sqlcmd STRING
    DEFINE te_client aim_vectors.t_client
    DEFINE te_request aim_vectors.t_text_embedding_request
    DEFINE te_response aim_vectors.t_text_embedding_response

    CALL _init_vector_embedding_request(ai_provider,te_client,te_request)

    SELECT COUNT(*) INTO tt FROM famquote

    LET sqlcmd = SFMT("UPDATE famquote SET emb = %1 WHERE pkey = ?", _vector_sql_placeholder(c_vector_dimension))
--display "SQL:", sqlcmd
    PREPARE stmt2 FROM sqlcmd
    DECLARE c_compute_vectors CURSOR FROM "SELECT pkey, author, language, quote FROM famquote ORDER BY pkey"
    FOREACH c_compute_vectors INTO rec.*
        LET source = rec.author, " said: ", c_quote_delim, rec.quote, c_quote_delim
        LET x = x + 1
        MESSAGE SFMT("Computing vector: %1/%2", x, tt); CALL ui.Interface.refresh()
        CALL te_request.set_source(source)
        LET s = te_client.send_text_embedding_request(te_request,te_response)
        IF s < 0 THEN
            CALL _mbox_ok(SFMT("ERROR: Could not get text embedding from %1.\n Probably HTTP 429? Try again.",ai_provider))
            EXIT FOREACH
        END IF
        LET vector = te_response.get_vector()
--display "vector = ", vector
        EXECUTE stmt2 USING vector, rec.pkey
    END FOREACH

    MESSAGE ""

END FUNCTION

FUNCTION compute_search_vector(
    ai_provider STRING,
    source STRING
) RETURNS STRING

    DEFINE vector STRING
    DEFINE s INTEGER
    DEFINE te_client aim_vectors.t_client
    DEFINE te_request aim_vectors.t_text_embedding_request
    DEFINE te_response aim_vectors.t_text_embedding_response

    CALL _init_vector_embedding_request(ai_provider,te_client,te_request)

    MESSAGE "Waiting for answer..."; CALL ui.Interface.refresh()

    CALL te_request.set_source(source)
    LET s = te_client.send_text_embedding_request(te_request,te_response)
    IF s < 0 THEN
        CALL _mbox_ok(SFMT("ERROR: Could not get text embedding from %1.\n",ai_provider))
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
    max_cosine_similarity FLOAT,
    search_vector STRING,
    context_items DYNAMIC ARRAY OF t_context_item
) RETURNS INTEGER

    DEFINE x INTEGER
    DEFINE sqlcmd STRING
    DEFINE rec t_famquote
    DEFINE cosim FLOAT

    LET sqlcmd = SFMT("SELECT %1 cosim,",
                       _vector_sql_cosine_distance(
                          "emb",
                          _vector_sql_placeholder(c_vector_dimension)
                       )
                     ),
                     " pkey, author, language, quote FROM famquote ORDER BY cosim"
display "SQL: ", sqlcmd
    DECLARE c_fetch_related CURSOR FROM sqlcmd
    LET x = 0
    CALL context_items.clear()
    FOREACH c_fetch_related USING search_vector INTO cosim, rec.*
display rec.pkey, "  cosine similarity: ", (cosim using "--&.&&&&&&&"), "  max: ", max_cosine_similarity
        IF cosim > max_cosine_similarity THEN EXIT FOREACH END IF
        LET x = x+1
        LET context_items[x].pkey = rec.pkey
        LET context_items[x].data = rec.author, " said: ",
                   c_quote_delim, rec.quote, c_quote_delim
    END FOREACH

    RETURN context_items.getLength()

END FUNCTION

FUNCTION _vector_sql_data_type(dimension INTEGER) RETURNS STRING
    CASE fgl_db_driver_type()
    WHEN "ora" RETURN SFMT("VECTOR(%1,FLOAT32)",dimension)
    OTHERWISE  RETURN SFMT("VECTOR(%1)",dimension) -- PostgreSQL
    END CASE
END FUNCTION

FUNCTION _vector_sql_cosine_distance(op1 STRING, op2 STRING) RETURNS STRING
    CASE fgl_db_driver_type()
    WHEN "pgs" RETURN SFMT("((%1) <=> (%2))", op1, op2)
    WHEN "ora" RETURN SFMT("VECTOR_DISTANCE((%1), (%2), COSINE)", op1, op2)
    WHEN "snc" RETURN SFMT("VECTOR_DISTANCE('cosine', (%1), (%2))", op1, op2)
    OTHERWISE  RETURN "?"
    END CASE
END FUNCTION

FUNCTION _vector_sql_placeholder(dimension INTEGER) RETURNS STRING
    CASE fgl_db_driver_type()
    WHEN "pgs" RETURN SFMT("?::vector(%1)",dimension)
    WHEN "ora" RETURN SFMT("VECTOR(?,%1,FLOAT32)",dimension)
    OTHERWISE  RETURN "?"
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

FUNCTION build_context_data(
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

FUNCTION send_question_to_ai(
    ai_provider STRING,
    system_message STRING,
    context_data STRING,
    question STRING
) RETURNS STRING

    DEFINE result STRING

    DEFINE s, x INTEGER
    --
    DEFINE ant_client aim_anthropic.t_client
    DEFINE ant_request aim_anthropic.t_message_request
    DEFINE ant_response aim_anthropic.t_response
    --
    DEFINE oai_client aim_openai.t_client
    DEFINE oai_request aim_openai.t_response_request
    DEFINE oai_response aim_openai.t_response
    --
    DEFINE gem_client aim_gemini.t_client
    DEFINE gem_request aim_gemini.t_text_request
    DEFINE gem_response aim_gemini.t_text_response
    --
    DEFINE mis_client aim_mistral.t_client
    DEFINE mis_request aim_mistral.t_chat_request
    DEFINE mis_response aim_mistral.t_chat_response

    MESSAGE "Waiting for answer..."; CALL ui.Interface.refresh()

    CASE ai_provider
    WHEN c_ai_provider_openai
        CALL oai_client.set_defaults("gpt-4o")
        CALL oai_request.set_defaults(oai_client)
        LET oai_request.temperature = 1.2
    WHEN c_ai_provider_mistral
        CALL mis_client.set_defaults("mistral-large-latest")
        CALL mis_request.set_defaults(mis_client)
        LET mis_request.temperature = 1.2
    WHEN c_ai_provider_anthropic
        CALL ant_client.set_defaults("claude-haiku-4-5")
        CALL ant_request.set_defaults(ant_client)
        LET ant_request.temperature = 0.8
    WHEN c_ai_provider_gemini
        CALL gem_client.set_defaults("gemini-3-flash-preview")
        CALL gem_request.set_defaults(gem_client)
        LET gem_request.generationConfig.temperature = 1.2
    OTHERWISE
        DISPLAY "Invalid AI provider"
        EXIT PROGRAM 1
    END CASE

    IF length(system_message)>0 THEN
        CASE ai_provider
        WHEN c_ai_provider_openai     CALL oai_request.set_instructions(system_message)
        WHEN c_ai_provider_mistral    CALL mis_request.set_system_message(system_message)
        WHEN c_ai_provider_anthropic  CALL ant_request.set_system_message(system_message)
        WHEN c_ai_provider_gemini     CALL gem_request.set_system_instruction(system_message)
        END CASE
    END IF
    IF length(context_data)>0 THEN
        CASE ai_provider
        WHEN c_ai_provider_openai     LET x = oai_request.append_developer_input(context_data)
        WHEN c_ai_provider_mistral    LET x = mis_request.append_user_message(context_data)
        WHEN c_ai_provider_anthropic  LET x = ant_request.append_user_message(context_data)
        WHEN c_ai_provider_gemini     LET x = gem_request.append_user_content(context_data)
        END CASE
    END IF
    CASE ai_provider
    WHEN c_ai_provider_openai
        LET x = oai_request.append_user_input(c_quote_delim||question||c_quote_delim)
        LET s = oai_client.create_response(oai_request,oai_response)
        LET result = oai_response.get_output_message_content_text(1,1)
    WHEN c_ai_provider_mistral
        LET x = mis_request.append_user_message(c_quote_delim||question||c_quote_delim)
        LET s = mis_client.create_chat_completion(mis_request,mis_response)
        LET result = mis_response.get_content_text(1)
    WHEN c_ai_provider_anthropic
        LET x = ant_request.append_user_message(c_quote_delim||question||c_quote_delim)
        LET s = ant_client.create_message(ant_request,ant_response)
        LET result = ant_response.get_content_text(1)
    WHEN c_ai_provider_gemini
        LET x = gem_request.append_user_content(c_quote_delim||question||c_quote_delim)
        LET s = gem_client.create_response(gem_request,gem_response)
        LET result = gem_response.get_content_text(1)
    END CASE
    IF s<0 THEN
        DISPLAY SFMT("ERROR: Failed to ask question to %1",ai_provider)
        EXIT PROGRAM 1
    END IF

    MESSAGE ""

    RETURN result

END FUNCTION

PRIVATE FUNCTION _mbox_ok(msg STRING) RETURNS ()
    MENU "RAG sample" ATTRIBUTES(STYLE="dialog",COMMENT=msg)
        COMMAND "Ok" EXIT MENU
    END MENU
END FUNCTION
