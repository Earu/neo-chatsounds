## Fixes
- [x] Source sounds from the following repo https://github.com/PAC3-Server/chatsounds-valve-games
- [x] Suggestions are not all shown when typing in the chat e.g typing "bodybreak" does not bring up "aaaa bodybreak"
- [x] Having modifiers in groups breaks the group modifiers e.g "(world#2):pitch(0.4)", seems to be a parsing issue
- [x] chatsounds_enable 0, should also hide suggestions and not compile lists on initialize
- [x] The last sound of a bunch of sounds does not parse properly
- [x] Legacy modifiers assigned incorrectly, and arguments too, seems to have to do with waiting for a second char in the parser
- [ ] Loop modifier does not work
- [x] FFT data from chatsounds streams
- [ ] Face flexes when saying sounds based on FFT data
- [ ] nya#1%10 <- Stream cuts early, fix pitch down not changing duration
- [ ] :pitch(\[sin(t()*100)\]), the * in lua expressions is converted to :legacy_rep internally which breaks multiplications
- [x] circular reference in json when recompiling all lists fully

## Suggestions
- [x] Ability to load in any sound repository you want? (can be done by server owners with chatsounds/repo_config.json)
- [x] Hide away big messages with only/mostly sounds from the chat
- [x] Proper realm/sound blocking features?
- [ ] Stacking modifiers ? e.g world--50--50 becomes --25 internally?
- [x] Completion that completes your currently typed modifier
- [x] Completion that shows the realm you are selecting with #/select modifier
- [ ] Reverb modifier
- [ ] EQ modifier
- [x] Local saysound (concommand?)