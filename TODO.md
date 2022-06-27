## Fixes
- [x] Source sounds from the following repo https://github.com/PAC3-Server/chatsounds-valve-games
- [x] Suggestions are not all shown when typing in the chat e.g typing "bodybreak" does not bring up "aaaa bodybreak"
- [x] Having modifiers in groups breaks the group modifiers e.g "(world#2):pitch(0.4)", seems to be a parsing issue
- [x] chatsounds_enable 0, should also hide suggestions and not compile lists on initialize
- [x] The last sound of a bunch of sounds does not parse properly
- [x] Legacy modifiers assigned incorrectly, and arguments too, seems to have to do with waiting for a second char in the parser

## Suggestions
- [x] Ability to load in any sound repository you want? (can be done by server owners with chatsounds/repo_config.json)
- [ ] Proper realm/sound blocking features?
- [ ] Stacking modifiers ? e.g world--50--50 becomes --25 internally?
- [x] Completion that completes your currently typed modifier
- [ ] Completion that shows the realm you are selecting with #/select modifier
- [ ] Reverb modifier
- [ ] EQ modifier
- [ ] Local saysound (concommand?)