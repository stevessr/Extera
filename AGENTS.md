# extera agents files
- flutter, dart
- never edit on main branch, only dev, feature/* or any other branches
- AGPLv3 license
- git commits: use conventional commits, short lowercase messages. no detailed messages unless necessary.
- avoid nested functions (functions inside functions)
- use english language in code and comments
- don't comment every function/piece of code, only non-obvious or complicated parts
- write only to assets/l10n/intl_en.arb and assets/l10n/intl_ru.arb when writing new translation strings
- do not commit without user consent
- do not automate creating pull request/writing PR description

## adding new pages
register new routes in `lib/config/routes.dart`. don't push pages into router directly (e.g. using MaterialPageRoute)