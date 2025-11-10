Laserfingers

I’ve wanted to build this iPad game for _years_, ever since multitouch got really good. It was inspired by an iPad game where there are knives that cut your fingers when you are trying to push a button, Slice HD. I wanted to combine that with more “action” and maybe even some rhythm.

The core mechanic of the game is that there is a button you need to press and hold for some amount of time. And there are lasers sweeping across the screen. If the laser touches your finger (where you are touching the screen) it burns you and you lose. When you push the button it starts to “fill up” and once it’s full you win. If you let go it “drains” back to empty. The idea is you use multiple fingers that you place and remove to dodge the lasers and fill the button. Once the button is filled the screen “opens” and reveals the next level.

That’s the basics, but there’s tons of extensions. Multiple buttons, buttons that “lock” when full, buttons that enable or disable lasers. Lasers that turn on and off, that move in different patterns (eg sweeping back and forth, rotating, panning).

Let’s build Laserfingers! Scaffold a SwiftUI + SpriteKit app. Here’s a sketch of the main flow:

# GUI

Outside of the gameplay there's a simple set of menus.

## Splash screen

Built in iOS launch screen

## Main menu

Shows a title (LASERFINGERS) and a few options, has the same background as a level, and shows a couple lasers panning/rotating around.

Options:

- Play
- Settings
- About

## Settings

- Enable/disable sound
- Enable/disable haptics

## About

- By x0xrx
- See also Gernal — link

## Play

Select a level (shows finished with a check, current, locked), plus a "Back" button to go back to the main menu.

# Gameplay

- Load current level.
- Gameplay starts: “Turn on” lasers, light up buttons.
- Start with a single button and a single laser
- If you are touching the button it fills up slowly
- If you let go it drains slowly
- If a laser touches your finger you get zapped
- Every time you get zapped your max simultaneous touched goes down by 1
- If you run out of touches you die
- When you die you see Try again or Exit
- Exit takes you back to the level selection
- If you win we reveal the next level, start again

There should be a small HUD showing number of “touches” active, and current level
