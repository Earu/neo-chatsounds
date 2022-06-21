## Fixes
- [x] Suggestions are not all shown when typing in the chat e.g typing "bodybreak" does not bring up "aaaa bodybreak"
- [ ] Having modifiers in groups breaks the group modifiers e.g "(world#2):pitch(0.4)", seems to be a parsing issue
- [x] chatsounds_enable 0, should also hide suggestions and not compile lists on initialize

## To Add
- [ ] Source sounds from the following repo https://github.com/PAC3-Server/chatsounds-valve-games
- [ ] Ability to load in any sound repository you want?
- [ ] Proper realm/sound blocking features?
- [ ] Stacking modifiers ? e.g world--50--50 becomes --25 internally?