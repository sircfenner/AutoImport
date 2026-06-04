## 0.3.0

-   Autocompletes now use `const` instead of `local`
-   Context-awareness improved to recognise `const` statements

## 0.2.0

-   Adopted string-requires instead of instance-requires (this also means a GetService is now only 
    added when explicitly triggered, rather than being inserted to support instance requires as before)
-   Improved performance significantly (faster parser, much better module/instance tracking)
-   More context-aware: suggestions will no longer appear in some inappropriate places that they used to
    (for example, inside a local statement or a type declaration)
-   Improved layout and detail of autocomplete labels to indicate the path/service that will be inserted
-   Disambiguation hints for modules with the same name are displayed on autocomplete labels
-   Service completion items are now automatically generated from ReflectionService so will stay up-to-date

## 0.1.0

Initial version. Used instance-based requires. No release available.