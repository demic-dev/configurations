{ ... }:
{
  flake.homeModules.hister =
    { config, inputs, ... }:
    {
      imports = [ inputs.hister.homeModules.default ];

      services.hister = {
        enable = true;

        port = 4433;

        settings = {
          app = {
            directory = "${config.xdg.configHome}/hister";
            title = "Hister";
            search_url = "https://duckduckgo.com/?q={query}";
            access_token = "";
            user_handling = false;
            public = false;
            log_level = "info";
            log_file = "";
            log_format = "";
            open_results_on_new_tab = false;
            redirect_on_no_results = true;
            display_extractor_config = false;
            disable_previews = false;
            profiler = false;
          };

          indexer = {
            detect_languages = true;
            keep_stopwords = false;
            directories = [ ];
            max_file_size_mb = 10;
          };

          crawler = {
            timeout = 5;
            delay = 0;
            backend = "bidi";
            backend_options = {
              capture_delay = 1.5;
            };
            proxy = "";
            user_agent = "";
            headers = { };
            cookies = [ ];
            no_robots = false;
          };

          semantic_search = {
            enable = true;
            embedding_endpoint = "http://localhost:8080/v1/embeddings";
            embedding_model = "bekko";
            embedding_timeout = 300;
            dimensions = 384;
            max_context_length = 512;
            chunk_overlap = 50;
            max_embedding_batch_size = 8;
            query_prefix = "";
            document_prefix = "";
            similarity_threshold = 0.5;
            result_limit = 10;
            semantic_weight = 0.4;
            max_embedding_concurrency = 2;
          };

          # hotkeys = {
          #   web = {
          #     "/" = "focus_search_input";
          #     "?" = "show_hotkeys";
          #     "alt+d" = "delete_result";
          #     "alt+enter" = "open_result_in_new_tab";
          #     "alt+j" = "select_next_result";
          #     "alt+k" = "select_previous_result";
          #     "alt+o" = "open_query_in_search_engine";
          #     "alt+v" = "view_result_popup";
          #     "enter" = "open_result";
          #     "tab" = "autocomplete";
          #   };
          #   tui = { };
          # };
        };
      };
    };
}
