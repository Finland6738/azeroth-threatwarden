# Alerts and Coach

*Italiano: [[Avvisi e Coach|Alerts-and-Coach-it]]*

> **New in `v0.3.0`, not verified in game.** Which threat data WoW Forever really gives an addon, and whether the
> messages help in a real fight, are still to be checked; the cooldown and the wording are provisional.

A **warning** when a risk begins, and one short **piece of advice** with its reason. Both appear in a strip of the
[[Threat Monitor|Threat-Monitor]] tab, between the header of the enemy and the list. Nothing is ever written in chat,
yours included, and the addon never opens its window to show you an alert.

## The strip

![The strip of a damage dealer: a predicted rise, with its confidence](../specs/mockups/previews/coach-dps-nebula.webp)

| In the strip | Meaning |
|---|---|
| Orange strip and speech bubble | **advice** from the Coach |
| Coloured strip and a state badge (icon and word) | an **alert**: it stays 4 seconds, then the advice comes back |
| Arrow of dots | the base is a *prediction* |
| *HIGH* / *MEDIUM* | the confidence of an estimate or a prediction |
| Struck bell | the alerts are muted |
| *Advice appears during combat* | out of combat |

An empty strip in combat means there is nothing to advise right now. Hover the strip to read the whole message, **why**
(on which data it rests), its kind (*detected*, *calculated*, *estimated*, *predicted*), its confidence, and since when
it shows. The reason never says what caused anything: the addon cannot know it.

In a very low window the strip stays and the header of the list is hidden to keep the rows.

## Alerts

An alert is raised only when something **begins**: your state rises to Warning or Danger, or the unit holding the enemy
changes. Which ones you get depends on your role: you near or on top of the enemy's threat list, your margin as a tank,
the enemy you lost, your pet taking it, or another player in Danger (by default only when you are the tank). The same
kind of alert about the same unit waits 8 seconds before it comes again.

![An alert, with the border of the window in the colour of its state](../specs/mockups/previews/alert-danger-warden.webp)

By default the alert shows in the strip and the **border** of the window takes the colour of its state once, for about
two seconds, without flashing. With the message turned off, the pill at the top shows the state's icon for the same
time, so colour never carries the meaning alone. A **sound** is off by default; when on, it plays only for Danger and
for losing or taking the enemy.

### What to do at Warning and Danger

For a damage dealer or a healer the alerts of your own threat say what to do:

| Your threat | Damage dealer | Healer |
|---|---|---|
| **Warning** (from 82 %) | *Threat 85 %: ease off, fewer casts or lower ranks* | the same |
| **Danger** (from 91 %) | *Threat 93 %: stop damage for a moment* | *Threat 93 %: stop healing for a moment* |

"Lower ranks" means a lower rank of the same spell, which makes less threat; the addon never names a spell or a class.
A tank is never told to stop: holding the enemy, it gets the margin alerts on the second (from 82 % and 91 %); a tank
that does not hold it gets only *close to taking aggro* or *very close to taking aggro*. With *state only* data the
alert says what the game shows, without numbers.

### Muting

- `/atw mute`, or the [key you bind to it](Commands#key-binding), silences every alert **until the end of the current
  fight**; out of combat, until the end of the next one. Again to unmute sooner. A reload also ends it. The Coach is
  not muted: it is text in the strip (turn it off in [Settings](Settings#alerts)).
- **One unit**: right-click its row in the list and choose **Mute alerts about this unit** (again to unmute). It lasts
  until a reload, and no name is saved. Your own row has no such menu.

![The strip while the alerts are muted](../specs/mockups/previews/alert-muted-warden.webp)

### The game's own threat warning

World of Warcraft has its own threat warning in the game options. If it is on, you may get two warnings for the same
thing: turn off one of them. The addon never changes the game's setting.

## Alerts about other mobs

> **New in `v0.7.0`**, not verified in game.

By default the alerts speak only about the enemy the monitor follows. Turn on **Alerts about other mobs** in the
[Alerts card](Settings#alerts) to be told about the other mobs of a pull too (the ones of the
[[Dungeon Focus|Dungeon-Focus]]), when the game lets an addon read them.

| Alert | When | Who gets it |
|---|---|---|
| *A mob is on Kor* | someone who is not a tank takes a mob | as **Alerts about others** says (by default only a tank) |
| *Kor is about to pull a mob* | someone is close to taking a mob | as **Alerts about others** says |
| *A mob is not on the tank* | no tank is on the threat list of a mob (a warning, never with a sound) | as **Alerts about others** says |
| *Your threat on another mob is very high* | your own threat on another mob reaches Danger, close to taking it or holding it | you, unless you are the tank |

- Only a **new** condition speaks, and only a worse one: a mob that gets safer says nothing, a mob that cannot be read
  says nothing, and the mob that was your target says nothing when you leave it.
- The same mob waits the cooldown; the alerts about others come at most one every 3 seconds, the most serious first.
  The mute and the muted units apply, and a tank is never told about being close to pulling.
- With the window closed they reach you only while the **sound** is on.
- Nothing is written in chat and nothing of them is recorded: reports and replay hold the monitored enemy only.

## The Coach

One tip at a time for your role (tank, damage dealer or healer), for example *Threat rising: consider delaying your
burst*, *Ease off: less damage, fewer casts or lower ranks* (from 82 %), *Very close to taking aggro: stop damage for a
moment* (from 91 %; a healer reads *healing* instead of *damage*) or, for a tank, *the second may overtake you*. Every tip has its reason. It never names an ability or a class (the one advice about spells is the generic *lower ranks*),
and it says *Not enough data for advice* (with why) when the game does not give enough.

![Not enough data for advice, and why](../specs/mockups/previews/coach-unknown-nebula.webp)

![The strip of a tank: the second may overtake](../specs/mockups/previews/coach-tank-warden.webp)

Which threat data WoW Forever gives is still being checked: with *state only* data the messages have no numbers, and
with unreadable data there is nothing to alert about.
