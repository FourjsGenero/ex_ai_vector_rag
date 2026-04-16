IMPORT util

IMPORT FGL aim_anthropic
IMPORT FGL aim_openai
IMPORT FGL aim_gemini
IMPORT FGL aim_mistral
IMPORT FGL aim_vectors

TYPE t_item RECORD
       pkey INT,
       short_name STRING,
       category STRING,
       description STRING,
       emb TEXT
     END RECORD

TYPE t_item_attr RECORD
       pkey INT,
       short_name STRING,
       category STRING,
       description STRING,
       emb STRING
     END RECORD

TYPE t_context_item RECORD
       pkey INT,
       data STRING
     END RECORD

PRIVATE CONSTANT c_ai_provider_gemini = "gemini"
PRIVATE CONSTANT c_ai_provider_anthropic = "anthropic"
PRIVATE CONSTANT c_ai_provider_mistral = "mistral"
PRIVATE CONSTANT c_ai_provider_openai  = "openai"

TYPE t_parameters RECORD
  ai_provider STRING,
  ai_model STRING,
  data_file STRING,
  dbsource STRING,
  dbuser STRING,
  dbpswd STRING,
  max_cosine_similarity FLOAT,
  vector_dimension INTEGER
END RECORD

CONSTANT c_system_message STRING =
`<role>
You are a nice and friendly supermarket assistant.
</role>
<task>
You can answer customer questions about available items.
</task>
<instruction>
Focus on item descriptions provided within <items> and </items> XML markers.
Always mention the item short names in your answer.
If the provided items do not match the user question, just respond:
  "I need more information to help you."
</instruction>
`

MAIN
    DEFINE params t_parameters
    DEFINE params_file TEXT
    DEFINE dbserver STRING
    DEFINE x, s INTEGER
    DEFINE prev_ai_provider STRING
    DEFINE prev_vector_dim INTEGER
    DEFINE item_list DYNAMIC ARRAY OF t_item
    DEFINE item_list_attr DYNAMIC ARRAY OF t_item_attr
    DEFINE search_context STRING = "Sport articles"
    DEFINE search_vector STRING
    DEFINE context_data STRING
    DEFINE system_message STRING = c_system_message
    DEFINE context_items DYNAMIC ARRAY OF t_context_item
    DEFINE user_question STRING
         = "I am a tennis player, what do you suggest me?"
         #= "Can I find running shoes here?"
    DEFINE llm_response STRING

    OPEN FORM f1 FROM "ai_rag_items"
    DISPLAY FORM f1

    LOCATE params_file IN FILE "params.json"

    IF num_args()==0 THEN
       IF params_file.getLength()>0 THEN
          CALL util.JSON.parse(params_file,params)
       ELSE
          LET params.ai_provider = "anthropic"
          LET params.ai_model = "clause-opus-4-6"
          LET params.data_file = "items_1.json"
          LET params.dbsource = "test1+driver='dbmpgs_9'"
          LET params.dbuser = "pgsuser"
          LET params.dbpswd = "fourjs"
       END IF
    ELSE
       LET x = 0
       IF num_args()>=3 THEN
          LET params.ai_provider = arg_val(x:=x+1)
          LET params.ai_model = arg_val(x:=x+1)
          LET params.data_file = arg_val(x:=x+1)
       END IF
       IF num_args()>3 THEN
          LET params.dbsource = arg_val(x:=x+1)
          LET params.dbuser = arg_val(x:=x+1)
          LET params.dbpswd = arg_val(x:=x+1)
       END IF
    END IF
    IF params.max_cosine_similarity IS NULL THEN
       LET params.max_cosine_similarity = 0.45
    END IF
    IF params.vector_dimension IS NULL THEN
       LET params.vector_dimension = 1024
    END IF

    IF params.dbuser IS NULL THEN
        CONNECT TO params.dbsource
    ELSE
        CONNECT TO params.dbsource USER params.dbuser USING params.dbpswd
    END IF
    LET dbserver = fgl_db_driver_type()

    CALL aim_anthropic.initialize()
    CALL aim_openai.initialize()
    CALL aim_gemini.initialize()
    CALL aim_mistral.initialize()

    CALL aim_vectors.initialize()

    LET s = fill_item_list(item_list,params.vector_dimension)

    DIALOG ATTRIBUTES(UNBUFFERED)

        DISPLAY ARRAY item_list TO sr_item_list.*
        END DISPLAY

        INPUT BY NAME dbserver, params.dbsource,
                      params.ai_provider, params.ai_model,
                      params.vector_dimension,
                      system_message,
                      search_context,
                      params.max_cosine_similarity,
                      search_vector,
                      context_data,
                      user_question,
                      llm_response
            ATTRIBUTES(WITHOUT DEFAULTS)

            BEFORE FIELD ai_provider
               LET prev_ai_provider = params.ai_provider
            ON CHANGE ai_provider
               IF NOT _mbox_yn("Provider change implies vector re-calculation, proceed?") THEN
                  LET params.ai_provider = prev_ai_provider
                  CONTINUE DIALOG
               END IF
               LET prev_ai_provider = params.ai_provider
               LET params.ai_model = _default_model(params.ai_provider)
               LET search_vector = NULL
               UPDATE smitems SET emb = NULL
               LET s = fill_item_list(item_list,params.vector_dimension)
               CALL item_list_attr.clear()

            BEFORE FIELD vector_dimension
               LET prev_vector_dim = params.vector_dimension
            ON CHANGE vector_dimension
               IF NOT _mbox_yn("Dimension change implies SQL table re-init, proceed?") THEN
                  LET params.vector_dimension = prev_vector_dim
                  CONTINUE DIALOG
               END IF
               LET prev_vector_dim = params.vector_dimension
               LET search_vector = NULL
               CALL init_sql_table(params.data_file,params.vector_dimension)
               CALL item_list.clear()
               CALL item_list_attr.clear()

        END INPUT

        BEFORE DIALOG
           CALL DIALOG.setArrayAttributes("sr_item_list",item_list_attr)

        ON ACTION init_sql_table
           CALL init_sql_table(params.data_file,params.vector_dimension)
           CALL item_list.clear()
           CALL item_list_attr.clear()
           LET context_data = NULL
           LET llm_response = NULL
           MESSAGE "SQL Table initialized, ready to be filled with data"

        ON ACTION fill_item_list
           LET s = fill_item_list(item_list,params.vector_dimension)
           CALL item_list_attr.clear()
           LET context_data = NULL
           LET llm_response = NULL

        ON ACTION compute_vector_embeddings
           CALL compute_vector_embeddings(params.ai_provider,params.vector_dimension)
           LET s = fill_item_list(item_list,params.vector_dimension)
           CALL item_list_attr.clear()
           LET context_data = NULL
           LET llm_response = NULL

        ON ACTION search_vector
           LET context_data = NULL
           LET llm_response = NULL
           LET search_vector = compute_search_vector(params.ai_provider,
                                                     params.vector_dimension,
                                                     search_context)
           IF search_vector IS NULL THEN
               CALL _mbox_ok("Could not compute search vector.")
           END IF

        ON ACTION find_match
           LET llm_response = NULL
           IF search_vector IS NULL THEN
               CALL _mbox_ok("First you need to compute the search vector from context sentence.")
               CONTINUE DIALOG
           END IF
           LET x = find_matching_items(params.max_cosine_similarity,
                                       search_vector, params.vector_dimension,
                                       context_items)
           IF x == 0 THEN
               LET context_data = NULL
               CALL _mbox_ok("No matching items found in database!\nIncrease MAX cosine similarity.")
           ELSE
               LET context_data = build_context_data(search_context,context_items)
               CALL fill_item_list_attrs(item_list,context_items,item_list_attr)
               CALL _mbox_ok(SFMT("Found %1 matching items in database!",x))
           END IF

        ON ACTION ask_llm
           LET llm_response =
               send_question_to_ai(params.ai_provider, system_message, context_data, user_question)
           IF llm_response IS NOT NULL THEN
               NEXT FIELD llm_response
           END IF

        ON ACTION close
           EXIT DIALOG

    END DIALOG

    LET params_file = util.JSON.format(util.JSON.stringify(params))

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

FUNCTION init_sql_table(
    data_file STRING,
    vector_dimension INTEGER
) RETURNS ()

    DEFINE x INTEGER
    DEFINE sqlcmd STRING
    DEFINE arr DYNAMIC ARRAY OF t_item
    DEFINE data TEXT

    LOCATE data IN FILE data_file
    CALL util.JSON.parse(data,arr)

    WHENEVER ERROR CONTINUE
    DROP TABLE smitems
    WHENEVER ERROR STOP
    LET sqlcmd = "CREATE TABLE smitems ("
                  || " pkey INT,"
                  || " short_name VARCHAR(50),"
                  || " category VARCHAR(50),"
                  || " description VARCHAR(500),"
                  || SFMT(" emb %1", _vector_sql_data_type(vector_dimension) )
                  || ")"
--display "SQL: ", sqlcmd
    EXECUTE IMMEDIATE sqlcmd

    -- First insert rows without embeddings
    PREPARE stmt1 FROM "INSERT INTO smitems VALUES (?,?,?,?,NULL)"
    FOR x = 1 TO arr.getLength()
        EXECUTE stmt1 USING arr[x].pkey, arr[x].short_name,
                            arr[x].category, arr[x].description
    END FOR

END FUNCTION

-- Table may not yet exist.
FUNCTION fill_item_list(
    arr DYNAMIC ARRAY OF t_item,
    vector_dimension INTEGER
) RETURNS INTEGER
    DEFINE x INTEGER
    DEFINE sqlcmd STRING

    TRY
        SELECT COUNT(*) INTO x FROM smitems
    CATCH
        RETURN -1
    END TRY

    LET sqlcmd = "SELECT pkey, short_name, category, description"
                  || SFMT(", %1", _vector_sql_fetch_expr("emb",vector_dimension))
                  || " FROM smitems ORDER BY pkey"
--display "SQL:", sqlcmd
    DECLARE c_fill_list CURSOR FROM sqlcmd
    CALL arr.clear()
    OPEN c_fill_list
    LET x = 1
    WHILE sqlca.sqlcode == 0
        LOCATE arr[x].emb IN FILE
        FETCH c_fill_list INTO arr[x].*
        IF sqlca.sqlcode == NOTFOUND THEN
            EXIT WHILE
        END IF
        LET x = x+1
    END WHILE
    CALL arr.deleteElement(x)

    RETURN arr.getLength()

END FUNCTION

FUNCTION fill_item_list_attrs(
    item_list DYNAMIC ARRAY OF t_item,
    context_items DYNAMIC ARRAY OF t_context_item,
    item_list_attr DYNAMIC ARRAY OF t_item_attr
) RETURNS ()

    DEFINE x, n INTEGER

    CALL item_list_attr.clear()
    FOR x = 1 TO context_items.getLength()
        LET n = item_list.search("pkey",context_items[x].pkey)
        IF n>0 THEN
            LET item_list_attr[n].description = "green bold"
        END IF
    END FOR

END FUNCTION

FUNCTION _init_vector_embedding_request(
    ai_provider STRING,
    --ai_emb_model STRING,
    vector_dimension INTEGER,
    te_client aim_vectors.t_client INOUT,
    te_request aim_vectors.t_text_embedding_request INOUT
) RETURNS ()
    CASE ai_provider
    WHEN c_ai_provider_anthropic -- Must use VoyageAI for vector generation!
        CALL te_client.set_defaults("voyageai","voyage-3-large")
        CALL te_request.set_defaults(te_client,NULL)
    WHEN c_ai_provider_openai
        CALL te_client.set_defaults(ai_provider,"text-embedding-3-small")
        CALL te_request.set_defaults(te_client,vector_dimension)
    WHEN c_ai_provider_mistral
        CALL te_client.set_defaults(ai_provider,"mistral-embed")
        CALL te_request.set_defaults(te_client,NULL) -- dim is always 1024 with mistral
    WHEN c_ai_provider_gemini
        CALL te_client.set_defaults(ai_provider,"gemini-embedding-001")
        CALL te_request.set_defaults(te_client,vector_dimension)
    OTHERWISE
        DISPLAY "Unexpected AI provider: ", ai_provider
        EXIT PROGRAM 1
    END CASE
END FUNCTION

FUNCTION _build_context_data(
    rec t_item
) RETURNS STRING
    RETURN SFMT(`"%1" (%2): "%3"`, rec.short_name, rec.category, rec.description)
END FUNCTION

FUNCTION compute_vector_embeddings(
    ai_provider STRING,
    vector_dimension INTEGER
) RETURNS ()

    DEFINE s, x, tt INTEGER
    DEFINE rec t_item
    DEFINE source STRING
    DEFINE vector TEXT
    DEFINE sqlcmd STRING
    DEFINE te_client aim_vectors.t_client
    DEFINE te_request aim_vectors.t_text_embedding_request
    DEFINE te_response aim_vectors.t_text_embedding_response

    LOCATE vector IN MEMORY

    CALL _init_vector_embedding_request(ai_provider,vector_dimension,te_client,te_request)

    SELECT COUNT(*) INTO tt FROM smitems

    LET sqlcmd = SFMT("UPDATE smitems SET emb = %1 WHERE pkey = ?", _vector_sql_placeholder(vector_dimension))
--display "SQL:", sqlcmd
    PREPARE stmt2 FROM sqlcmd
    DECLARE c_compute_vectors CURSOR FROM "SELECT pkey, short_name, category, description FROM smitems ORDER BY pkey"
    FOREACH c_compute_vectors INTO rec.*
        LET source = _build_context_data(rec)
        LET x = x + 1
        MESSAGE SFMT("Computing vector: %1/%2", x, tt); CALL ui.Interface.refresh()
        CALL te_request.set_source(source)
        LET s = te_client.send_text_embedding_request(te_request,te_response)
        IF s < 0 THEN
            CALL _mbox_ok(SFMT("ERROR: Could not get text embedding from %1.\n Probably HTTP 429? Try again.",ai_provider))
            EXIT FOREACH
        END IF
        LET vector = te_response.get_vector()
--display "UPDATE with vector = ", vector
        EXECUTE stmt2 USING vector, rec.pkey
    END FOREACH

    MESSAGE ""

END FUNCTION

FUNCTION compute_search_vector(
    ai_provider STRING,
    vector_dimension INTEGER,
    source STRING
) RETURNS STRING

    DEFINE vector STRING
    DEFINE s INTEGER
    DEFINE te_client aim_vectors.t_client
    DEFINE te_request aim_vectors.t_text_embedding_request
    DEFINE te_response aim_vectors.t_text_embedding_response

    CALL _init_vector_embedding_request(ai_provider,vector_dimension,te_client,te_request)

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

FUNCTION find_matching_items(
    max_cosine_similarity FLOAT,
    search_vector STRING,
    vector_dimension INTEGER,
    context_items DYNAMIC ARRAY OF t_context_item
) RETURNS INTEGER

    DEFINE x INTEGER
    DEFINE sqlcmd STRING
    DEFINE rec t_item
    DEFINE cosim FLOAT
    DEFINE vector TEXT -- Required for SQL Server...

    LOCATE vector IN MEMORY
    LET vector = search_vector

    LET sqlcmd = SFMT("SELECT %1 cosim,",
                       _vector_sql_cosine_distance(
                          vector_dimension,
                          "emb",
                          _vector_sql_placeholder(vector_dimension)
                       )
                     ),
                     " pkey, short_name FROM smitems ORDER BY cosim"
display "SQL: ", sqlcmd
    DECLARE c_fetch_related CURSOR FROM sqlcmd
    LET x = 0
    CALL context_items.clear()
    FOREACH c_fetch_related USING vector INTO cosim, rec.pkey, rec.short_name
display rec.pkey, "  cosine similarity: ", (cosim using "--&.&&&&&&&"), "  max: ", max_cosine_similarity
        IF cosim > max_cosine_similarity THEN EXIT FOREACH END IF
        LET x = x+1
        LET context_items[x].pkey = rec.pkey
        LET context_items[x].data = _build_context_data(rec)
    END FOREACH

    RETURN context_items.getLength()

END FUNCTION

FUNCTION _vector_sql_data_type(vector_dimension INTEGER) RETURNS STRING
    CASE fgl_db_driver_type()
    WHEN "pgs" RETURN SFMT("VECTOR(%1)",vector_dimension)
    WHEN "ora" RETURN SFMT("VECTOR(%1,FLOAT32)",vector_dimension)
    WHEN "snc" RETURN SFMT("VECTOR(%1,FLOAT32)",vector_dimension)
    OTHERWISE RETURN "?"
    END CASE
END FUNCTION

FUNCTION _vector_sql_cosine_distance(vector_dimension INTEGER, op1 STRING, op2 STRING) RETURNS STRING
    CASE fgl_db_driver_type()
    WHEN "pgs" RETURN SFMT("((%1) <=> (%2))", op1, op2)
    WHEN "ora" RETURN SFMT("VECTOR_DISTANCE((%1), (%2), COSINE)", op1, op2)
    -- SQL Server bug? Must cast STRING/TEXT parameter to VECTOR!
    WHEN "snc" RETURN SFMT("VECTOR_DISTANCE('cosine', (%1), CAST(%2 AS VECTOR(%3)) )", op1, op2, vector_dimension)
    OTHERWISE RETURN "?"
    END CASE
END FUNCTION

FUNCTION _vector_sql_placeholder(vector_dimension INTEGER) RETURNS STRING
    CASE fgl_db_driver_type()
    WHEN "pgs" RETURN SFMT("?::vector(%1)",vector_dimension)
    WHEN "ora" RETURN SFMT("VECTOR(?,%1,FLOAT32)",vector_dimension)
    WHEN "snc" RETURN "?"
    OTHERWISE  RETURN "?"
    END CASE
END FUNCTION

FUNCTION _vector_sql_fetch_expr(expr STRING, vector_dimension INTEGER) RETURNS STRING
    LET vector_dimension = NULL
    CASE fgl_db_driver_type()
    WHEN "pgs" RETURN SFMT("%1::text",expr)
    WHEN "ora" RETURN expr -- Must be fetched into TEXT !
    WHEN "snc" RETURN SFMT("CAST(%1 AS VARCHAR(MAX))",expr) -- Fetch into TEXT!
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
    CALL result_set.append(search_context || ":")
    CALL result_set.append("<items>")
    FOR x = 1 TO context_items.getLength()
        CALL result_set.append("\n- "||context_items[x].data)
    END FOR
    CALL result_set.append("\n</items>")
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
        LET x = oai_request.append_user_input(question)
        LET s = oai_client.create_response(oai_request,oai_response)
        LET result = oai_response.get_output_message_content_text(1,1)
    WHEN c_ai_provider_mistral
        LET x = mis_request.append_user_message(question)
        LET s = mis_client.create_chat_completion(mis_request,mis_response)
        LET result = mis_response.get_content_text(1)
    WHEN c_ai_provider_anthropic
        LET x = ant_request.append_user_message(question)
        LET s = ant_client.create_message(ant_request,ant_response)
        LET result = ant_response.get_content_text(1)
    WHEN c_ai_provider_gemini
        LET x = gem_request.append_user_content(question)
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

PRIVATE FUNCTION _mbox_yn(msg STRING) RETURNS BOOLEAN
    DEFINE r BOOLEAN
    MENU "RAG sample" ATTRIBUTES(STYLE="dialog",COMMENT=msg)
        COMMAND "Yes" LET r=TRUE
        COMMAND "No"  LET r=FALSE
    END MENU
    RETURN r
END FUNCTION
