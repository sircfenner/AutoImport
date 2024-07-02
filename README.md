This plugin adds autocomplete suggestions to the Roblox Studio script editor for ModuleScripts in
your project as well as Services that can be imported via GetService. Just begin typing the name of
a ModuleScript or a Service and then select it from the autocomplete list.

<div align="center">

https://github.com/sircfenner/AutoImport/assets/25118482/0d9222e1-8094-4982-a716-6d8b8f111d3a

</div>

### Useful features

-   When requiring a ModuleScript, a GetService call may be automatically inserted to enable accessing
    the module in the canonical way; if the service was already imported, it will use the variable
    assigned to it instead
-   Suggestions are sensitive to Luau syntax/context; for example, they will not appear while typing
    in comments or strings other than in the expression parts of interpolated strings
-   Comment directives/hot comments at the top of the file (such as `--!strict`) are respected when
    inserting code
-   Network boundaries and common practices for locating server/client-specific code are respected;
    for example, inaccessible server modules are not suggested from client scripts
-   Modules that are descendants of folders with names typically used by package managers
    ('node_modules' and '\_Index') are removed from autocomplete suggestions
-   Service completions are derived from the API dump at the time of building the plugin, so you can
    re-build the plugin yourself following the steps below to stay up to date with the latest service
    names

### Installing the plugin

You can pay for a pre-built version of the plugin via the 
[Roblox Creator Store](https://create.roblox.com/store/asset/18297441605/Auto-Import). Alternatively,
follow the steps below to build it yourself, then add it to your local plugins folder.

### Building the plugin

To build this plugin yourself:

1. Clone the repo
2. Install [foreman](https://github.com/Roblox/foreman), then run `foreman install`
3. Run `scripts/build.sh`

If you are interested in making a contribution, run `scripts/dev.sh` with the `Reload plugins on
file changed` setting enabled in Studio. This will hot-reload the plugin as you make edits.

### See also

Existing plugin with similar functionality: <https://github.com/MonzterDev/Roblox-Auto-Import>
