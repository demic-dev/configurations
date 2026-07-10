{ ... }:
{
  flake.homeModules.zen =
    { pkgs, inputs, ... }:
    let
      firefox-addons = inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system};
    in
    {
      imports = [ inputs.zen-browser.homeModules.beta ];

      programs.zen-browser = {
        enable = true;
        setAsDefaultBrowser = true;

        policies = {
          AutofillAddressEnabled = false;
          AutofillCreditCardEnabled = false;
          DisableAppUpdate = true;
          DisableTelemetry = true;
          OfferToSaveLogins = false;
          EnableTrackingProtection = {
            Value = true;
            Locked = true;
            Cryptomining = true;
            Fingerprinting = true;
          };
        };

        profiles.default = {
          id = 0;
          isDefault = true;
          name = "Default Profile";
          path = "9xls3g71.Default Profile";

          # about:config prefs, extracted from the live profile's prefs.js and
          # filtered down to genuine preferences: volatile runtime state (update
          # timestamps, telemetry counters/IDs, sync/fxaccounts secrets, install
          # versions, one-shot migration flags, UI geometry) was deliberately
          # excluded so nothing stale or sensitive gets frozen into user.js.
          # Includes mod settings (mod.*/psu.*/theme.*/zen.mods.*).
          settings = {
            "browser.ctrlTab.sortByRecentlyUsed" = false;

            # Toolbar disposition (which widgets live in which area and their
            # order), i.e. the "Customize toolbar" layout. Written as a Nix
            # attrset via builtins.toJSON so it stays editable. Because this is
            # pinned in user.js, UI-side rearranging won't persist across a
            # rebuild — edit here instead. Widget IDs for extensions not in
            # extensions.packages are simply ignored by Zen.
            "browser.uiCustomization.state" = builtins.toJSON {
              placements = {
                "widget-overflow-fixed-list" = [ ];
                "unified-extensions-area" = [
                  "canvasblocker_kkapsner_de-browser-action"
                  "jid1-zadieub7xozojw_jetpack-browser-action"
                  "_74145f27-f039-47ce-a470-a662b129930a_-browser-action"
                  "myallychou_gmail_com-browser-action"
                  "_4f391a9e-8717-4ba6-a5b1-488a34931fcb_-browser-action"
                  "leechblockng_proginosko_com-browser-action"
                ];
                "nav-bar" = [
                  "back-button"
                  "forward-button"
                  "stop-reload-button"
                  "customizableui-special-spring1"
                  "developer-button"
                  "find-button"
                  "vertical-spacer"
                  "urlbar-container"
                  "ublock0_raymondhill_net-browser-action"
                  "_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action"
                  "customizableui-special-spring2"
                  "unified-extensions-button"
                  "reset-pbm-toolbar-button"
                ];
                "toolbar-menubar" = [
                  "menubar-items"
                ];
                TabsToolbar = [
                  "tabbrowser-tabs"
                ];
                "vertical-tabs" = [ ];
                PersonalToolbar = [
                  "import-button"
                  "personal-bookmarks"
                ];
                "zen-sidebar-top-buttons" = [
                  "zen-toggle-compact-mode"
                ];
                "zen-sidebar-foot-buttons" = [
                  "downloads-button"
                  "zen-workspaces-button"
                  "zen-create-new-button"
                ];
              };
              seen = [
                "developer-button"
                "screenshot-button"
                "_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action"
                "jid1-zadieub7xozojw_jetpack-browser-action"
                "ublock0_raymondhill_net-browser-action"
                "_74145f27-f039-47ce-a470-a662b129930a_-browser-action"
                "myallychou_gmail_com-browser-action"
                "_4f391a9e-8717-4ba6-a5b1-488a34931fcb_-browser-action"
                "canvasblocker_kkapsner_de-browser-action"
                "leechblockng_proginosko_com-browser-action"
                "papis_connector_wavefrontshaping_net-browser-action"
              ];
              dirtyAreaCache = [
                "nav-bar"
                "vertical-tabs"
                "zen-sidebar-foot-buttons"
                "PersonalToolbar"
                "unified-extensions-area"
                "toolbar-menubar"
                "TabsToolbar"
                "zen-sidebar-top-buttons"
              ];
              currentVersion = 24;
              newElementCount = 9;
            };

            "browser.urlbar.showSearchSuggestionsFirst" = false;
            "browser.urlbar.suggest.engines" = true;
            "browser.urlbar.suggest.openpage" = true;
            "browser.urlbar.suggest.searches" = false;

            "dom.forms.autocomplete.formautofill" = true;
            "dom.security.https_only_mode" = true;

            "intl.accept_languages" = "it,en-us,en,fr,es";
            "layout.spellcheckDefault" = 0;
            "media.eme.enabled" = false;

            "network.trr.mode" = 2;
            "network.trr.uri" = "https://firefox.dns.nextdns.io/";
            "privacy.annotate_channels.strict_list.enabled" = true;
            "privacy.bounceTrackingProtection.mode" = 1;
            "privacy.clearOnShutdown_v2.formdata" = true;
            "privacy.fingerprintingProtection" = true;
            "privacy.query_stripping.enabled" = true;
            "privacy.query_stripping.enabled.pbmode" = true;
            "privacy.trackingprotection.allow_list.convenience.enabled" = false;
            "privacy.trackingprotection.consentmanager.skip.pbmode.enabled" = false;
            "privacy.trackingprotection.emailtracking.enabled" = true;
            "privacy.trackingprotection.socialtracking.enabled" = true;
            "sidebar.visibility" = "hide-sidebar";
            "signon.management.page.breach-alerts.enabled" = false;

            "theme.custom_menubutton.custom" = "url(chrome://branding/content/icon32.png)";
            "theme.custom_menubutton.default" = "";
            "theme.zen-minimal-exit-menu.enable-icon-visibility" = false;
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

            "zen.tabs.ctrl-tab.ignore-essential-tabs" = true;
            "zen.tabs.select-recently-used-on-close" = false;
            "zen.view.compact.enable-at-startup" = true;
            "zen.view.use-single-toolbar" = false;

            # Audio Indicator Enhanced
            "zen.mods.AudioIndicatorEnhanced.audioWave.colorMuted" = "color-mix(in srgb, -moz-dialogtext 50%, rgb(129, 0, 0) 50%)";
            "zen.mods.AudioIndicatorEnhanced.audioWave.colorPlaying" = "-moz-dialogtext";
            "zen.mods.AudioIndicatorEnhanced.audioWave.enabled" = false;
            "zen.mods.AudioIndicatorEnhanced.audioWave.opacity" = "0.2";
            "zen.mods.AudioIndicatorEnhanced.bigEssentialIcons.enabled" = false;
            "zen.mods.AudioIndicatorEnhanced.hoverScaleAnimationEnabled" = true;
            "zen.mods.AudioIndicatorEnhanced.returnOldIcons" = true;
            "zen.mods.AudioIndicatorEnhanced.reverseAudioIcons" = false;

            # Better Find Bar Mod
            "theme-better_find_bar-enable_custom_background" = false;
            "theme.better_find_bar.custom_background" = "#112233";
            "theme.better_find_bar.hide_find_status" = false;
            "theme.better_find_bar.hide_found_matches" = false;
            "theme.better_find_bar.hide_highlight" = "not_hide";
            "theme.better_find_bar.hide_match_case" = "not_hide";
            "theme.better_find_bar.hide_match_diacritics" = "not_hide";
            "theme.better_find_bar.hide_whole_words" = "not_hide";
            "theme.better_find_bar.horizontal_position" = "default";
            "theme.better_find_bar.instant_animations" = false;
            "theme.better_find_bar.textbox_width" = "800";
            "theme.better_find_bar.transparent_background" = true;
            "theme.better_find_bar.vertical_position" = "top";
          };

          # UUIDs from the Zen mod store; these are the ones currently enabled.
          # Browse/find more at https://zen-browser.app/mods
          mods = [
            "906c6915-5677-48ff-9bfc-096a02a72379" # Floating Status Bar
            "2317fd93-c3ed-4f37-b55a-304c1816819e" # Audio Indicator Enhanced
            "a6335949-4465-4b71-926c-4a52d34bc9c0" # Better Find Bar
            "f7c71d9a-bce2-420f-ae44-a64bd92975ab" # Better Unloaded Tabs
            "9bbaab67-a2c8-4d79-837f-90cd72a8932a" # Big Essentials
          ];

          extensions = {
            force = true;
            packages = with firefox-addons; [
              ublock-origin
              bitwarden
              clearurls
              leechblock-ng
              canvasblocker
              # youtube-recommended-videos # "Unhook — Remove YouTube Recommended & Shorts"
            ];

            # uBlock Origin filter lists
            settings."uBlock0@raymondhill.net" = {
              force = true;
              settings.selectedFilterLists = [
                "user-filters"
                "ublock-filters"
                "ublock-badware"
                "ublock-privacy"
                "ublock-quick-fixes"
                "ublock-unbreak"
                "easylist"
                "easyprivacy"
                "urlhaus-1"
                "plowe-0"
              ];
            };
          };

          search = {
            force = true;
            default = "ddg";
            engines = {
              # Hide the built-in "config" engines (they can't be deleted, only
              # hidden). Keyed by engine id, not display name. ddg is kept as
              # the default above.
              google.metaData.hidden = true;
              bing.metaData.hidden = true;
              ecosia.metaData.hidden = true;
              perplexity.metaData.hidden = true;
              qwant.metaData.hidden = true;
              wikipedia.metaData.hidden = true; # built-in "Wikipedia (en)"

              "Wikipedia" = {
                name = "Wikipedia";
                urls = [
                  { template = "https://en.wikipedia.org/wiki/Special:Search?search={searchTerms}"; }
                ];
                definedAliases = [ "@wiki" ];
              };

              "Word Reference (en/it)" = {
                name = "Word Reference (en/it)";
                urls = [
                  { template = "https://www.wordreference.com/iten/{searchTerms}"; }
                  { template = "https://www.wordreference.com/enit/{searchTerms}"; }
                ];
                definedAliases = [ "@enit" ];
              };

              "NixOS Packages" = {
                name = "NixOS Packages";
                urls = [
                  { template = "https://search.nixos.org/packages?channel=unstable&type=packages&query={searchTerms}"; }
                ];
                icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
                definedAliases = [ "@np" ];
              };

              "NixOS Options" = {
                name = "NixOS Options";
                urls = [
                  { template = "https://search.nixos.org/options?channel=unstable&type=options&query={searchTerms}"; }
                ];
                icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
                definedAliases = [ "@no" ];
              };
            };
          };

          # ---- Spaces (MOCK) --------------------------------------------------
          # Placeholder only — replace `spaces` with your real ones, then flip
          # spacesForce to true to make the declared set authoritative (it deletes
          # spaces not listed here). Left false for now so nothing is destroyed.
          # ⚠ Close Zen before `home-manager switch` once spacesForce is enabled.
          spacesForce = false;
          spaces = {
            "Personal" = {
              id = "00000000-0000-0000-0000-000000000001";
              position = 1000;
              icon = "🏠";
            };
          };
        };
      };
    };
}
