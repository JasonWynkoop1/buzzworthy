# Buzzworthy for Apple TV

This is the Apple TV app for Buzzworthy. The Apple TV shows the game board, and everyone plays on their phones exactly like before (they scan the QR code, or go to **buzzworthy-one.vercel.app/play** and type the room code). The app runs the same game rules as the website, so nothing changes for players.

You only need the Mac once, to put the app on the Apple TV. After that the app sits on the Apple TV home screen like any other app.

## What you need

- Your Mac with **Xcode** installed (version 16 or newer)
- Your **Apple Developer account** (the Apple ID you use for it)
- The Apple TV and the Mac on the **same Wi-Fi**
- The Apple TV running tvOS 17 or newer (Settings > System > Software Updates if it is older)

## Step 1: Open the project on the Mac

1. Download **BuzzworthyTV.zip** onto the Mac and double-click it. A folder called **BuzzworthyTV** appears (usually in Downloads).
2. Open that folder and double-click **BuzzworthyTV.xcodeproj**. Xcode opens the project.
3. If Xcode asks whether you trust the project, click **Trust and Open**.

## Step 2: Tell Xcode who you are (only the first time)

1. In the menu bar at the top of the screen, click **Xcode**, then **Settings...** (on older Xcode it is called **Preferences...**).
2. Click the **Accounts** tab.
3. If your developer Apple ID is already listed, close this window and skip to Step 3.
4. Otherwise click the **+** button in the bottom left, choose **Apple ID**, click **Continue**, and sign in. Then close the window.

## Step 3: Sign the app with your account

1. In the left sidebar of the Xcode window, click the blue **BuzzworthyTV** icon at the very top.
2. In the middle area, under **TARGETS**, click **BuzzworthyTV**.
3. Click the **Signing & Capabilities** tab near the top.
4. Make sure **Automatically manage signing** has a check mark.
5. Click the **Team** drop-down and choose your name or your developer team.
6. Wait a few seconds. If a red message says the **Bundle Identifier** is not available, click into the **Bundle Identifier** box and change it to something unique, for example `com.yourname.buzzworthy`. The red message goes away.

## Step 4: Connect the Apple TV to Xcode (only the first time)

1. On the **Apple TV**, open **Settings**, then **Remotes and Devices**, then **Remote App and Devices**. Leave the TV on this screen.
2. On the **Mac**, in the Xcode menu bar click **Window**, then **Devices and Simulators**.
3. Click the **Devices** tab at the top of that window. Your Apple TV appears in the list on the left (it can take up to a minute).
4. Click your Apple TV, then click **Pair**.
5. A code appears on the TV. Type it into the box on the Mac and click **Connect**.
6. When it finishes, close the Devices window.
7. On the **Apple TV**, go to **Settings**, then **Privacy & Security**, then **Developer Mode**, and turn it **On**. The Apple TV restarts. After it restarts, confirm by choosing **Turn On** if it asks.

## Step 5: Install the app

1. At the top of the Xcode window, in the middle, there is a box that says **BuzzworthyTV** followed by a device name. Click the device name.
2. Pick your **Apple TV** from the list (it is under the devices section, above the simulators).
3. Click the **Play** button (the triangle) in the top left of Xcode, or press **Command + R**.
4. The first time can take several minutes while Xcode prepares the Apple TV. You will see progress at the top of the Xcode window.
5. When it is done, Buzzworthy opens on the TV and shows the QR code and room code. That's it!

You can now quit Xcode. The **Buzzworthy** app stays on the Apple TV home screen. With a paid developer account it keeps working for a year. If it ever stops opening, just repeat Step 5 to refresh it.

## Playing with the Siri Remote

- **Swipe** on the remote to move between buttons and board tiles. **Click** to press.
- In the lobby, click the question packs to switch them on or off, then click **Start game**.
- On the board, players pick clues on their phones, but you can also pick a tile with the remote.
- The **Play/Pause** button means **Continue** (after an answer is shown, between rounds, and during the final).
- If a host has joined, the TV also shows **Open buzzers**, **Correct** and **Wrong** buttons as a backup in case the host's phone dies.
- **New room code** (in the lobby) starts a fresh room with a new code.
- Pressing the **Back/Menu** button leaves the app. If you leave in the middle of a game, opening the app again keeps the same game as long as the Apple TV did not close it.

## If something goes wrong

- **The Apple TV does not show up in Xcode:** make sure both are on the same Wi-Fi, the TV is awake and on the Remote App and Devices screen, then quit and reopen Xcode.
- **"Developer Mode disabled" error:** do the last part of Step 4 (Privacy & Security, Developer Mode, On).
- **Signing errors in red:** go back to Step 3 and make sure a Team is chosen, and try a different Bundle Identifier.
- **Phones can't join:** the Apple TV needs internet. If the top of the screen says "Reconnecting to the internet", check the Apple TV's network.
