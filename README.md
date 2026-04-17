This plugin adds autocomplete suggestions to the Roblox Studio script editor for ModuleScripts (via 
require) and Services (via GetService). Just begin typing the name of a ModuleScript or a Service and
select it from the autocomplete list.

<div align="center">

https://github.com/user-attachments/assets/6cbf72ba-6223-4959-832b-212a3a1ad0c9

</div>

### Improvements in new version

-   Adopted string-requires instead of instance-requires (this also means a GetService is now only 
    added when explicitly triggered, rather than being inserted to support instance requires as before)
-   Improved performance significantly (faster parser, much better module/instance tracking)
-   More context-aware: suggestions will no longer appear in some inappropriate places that they used to
    (for example, inside a local statement or a type declaration)
-   Improved layout and detail of autocomplete labels to indicate the path/service that will be inserted
-   Disambiguation hints for modules with the same name are displayed on autocomplete labels
-   Service completion items are now automatically generated from ReflectionService so will stay up-to-date

### Useful features

-   When there are multiple modules with the same name, a minimal disambiguation path will be displayed
-   Suggestions are sensitive to Luau syntax/context; for example, they will not appear while typing
    in comments or strings other than in the expression parts of interpolated strings
-   Comment directives/hot comments at the top of the file (such as `--!strict`) are respected when
    inserting code
-   Network boundaries and common practices for locating server/client-specific code are respected;
    for example, inaccessible server modules are not suggested from client scripts
-   Modules that are descendants of folders with names typically used by package managers
    ('node_modules' and '\_Index') are removed from autocomplete suggestions
-   Automatically uses relative require paths when an imported module is a sibling or descendant

### Installing the plugin

You can get a pre-built version of the plugin in Releases or via the 
[Roblox Creator Store](https://create.roblox.com/store/asset/18297441605/Auto-Import). Alternatively,
follow the steps below to build it yourself, then add it to your local plugins folder.

### Building the plugin

To build this plugin yourself:

1. Clone the repo
2. Install [rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` in the repo
3. Run `scripts/build.sh`

To test local changes to the plugin, run `scripts/dev.sh` with the `Reload plugins on
file changed` setting enabled in Studio. This will hot-reload the plugin as you make edits.

