# neo-chatsounds

***Memes in the Garry's Mod chat.***

## What is this?
This repository is a Garry's Mod addon that adds `chat sounds` in your game. It suggests a list of sounds you can play when typing. *There are thousands of sounds available.*

It also comes with a twist: you can modify each sounds with **`modifiers`**.

## How do I know what sounds exist?
You have multiple options here:

1) Check the various repositories used to build the sound list
	- https://github.com/Metastruct/garrysmod-chatsounds
	- https://github.com/PAC3-Server/chatsounds
	- https://github.com/PAC3-Server/chatsounds-valve-games
2) Type various things in the chat and scroll through the suggestions made.

## How do I add sounds?
Typically you can either add sounds in [this repo]([https://github.com/PAC3-Server/chatsounds-valve-games]) or in [this one](https://github.com/PAC3-Server/chatsounds). Each of them are maintained by different people but the rules for adding a sound are the same.

**`Do check their readme.md!`**

## Modifiers ?
Modifiers are a big part of chatsounds, they also you to transform sounds and make them into something else. [Some people even made songs with them!](https://soundcloud.com/capsadmin).

### Here's an example:

- *Normal unmodified sounds:*
	```
	standing here i realize
	```
- *With a pitch modifier:*
	```
	standing here:pitch(0.5) i realize
	```

	This will in turn `pitch down` the first sound. You can also group sounds together:

	```
	(standing here i realize):pitch(0.8)
	```
- *Legacy modifiers:*
	```
	standing here%50 i realize
	```

	Wait a minute what is this?

	*Because chatsounds has a lot of legacy some syntax was also kept in as back-compatbility so that people's favorite ways of messing with chatsounds don't just disappear!*

	The above is a legacy pitch modifier, **instead of working from -5 to 5** like the current pitch modifier does **it works from 1 to 255**

### Where can I find a list of modifiers?
Right now there has never been a documentation made for the chatsounds syntax, or what modifiers exist, I do plan on making one though!

## What is this useful for?
Absolutely nothing, this is only for fun and it is very possible that you may not see any added value to it. If you wish to see it in action you can always join these servers:
- Meta Construct EU #1 - steam://connect/g1.metastruct.net
- Meta Construct EU #2 - steam://connect/g2.metastruct.net
- Meta Construct US #3 - steam://connect/g3.metastruct.net

## Contributing
Any contribution is welcome so long as it **`TESTED`** before. Please do respect the existing coding conventions (naming, etc...) and make sure your code is optimized, performances matter **especially in this project**.