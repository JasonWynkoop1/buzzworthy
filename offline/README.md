# Buzzworthy

A party trivia board game. The board runs on your TV, and every player uses their phone as a buzzer.

## What you need

- A computer with [Node.js](https://nodejs.org) 18 or newer (no other installs needed)
- A TV with a web browser, or a laptop plugged into the TV (HDMI, AirPlay, Chromecast tab cast, etc.)
- Everyone's phones on the **same Wi-Fi** as the computer

## Start it

```
cd buzzworthy
node server.js
```

It prints a link like `http://192.168.1.23:3000`. Open that link on the TV (or on the laptop connected to the TV). Players scan the QR code on screen, type their name, and they're in.

If your computer asks whether to allow Node to accept network connections, click **Allow**, or phones won't be able to connect.

## Playing with a host (recommended)

One person can be the host instead of a player. On the join screen, the host types their name and taps **Join as the host**.

- The host's phone shows each clue **and its answer**. Nobody else sees the answer.
- The host reads the clue out loud, then taps **Open buzzers**.
- Whoever buzzes first says their answer out loud. The host taps **Correct** or **Wrong**, and the scores update.
- Daily Double wagers are still entered on the player's phone, and the answer is spoken out loud.
- The Final Showdown uses typed answers, so everyone answers secretly. The host sees each answer as it comes in and can tap **Flip** if the automatic check gets one wrong.
- The host gets all the captain controls: picking packs, Start, Skip, Continue, and so on. The host can also tap a clue on their phone for whoever is picking.

If the host's phone dies, the TV has backup buttons in the bottom right: **Open buzzers (B)**, **Correct (C)**, and **Wrong (W)**.

Without a host, players type their answers and the game checks them automatically.

## How to play

1. **Lobby:** the first player to join is the **captain** (marked with a star). The captain taps **Start game** when everyone's in.
2. **The board:** 6 categories, 5 clues each. The player in control picks a clue on their phone.
3. **Buzzing:** the clue appears on the TV. Buzzers unlock once there's been time to read it; the phone button turns red. Buzz too early and you're locked out for a split second.
4. **Answering:** the first buzz wins and types the answer on their phone. No need to phrase it as a question, and small typos are forgiven. Right answers add the value and give you control of the board. Wrong answers subtract it, and the others get a chance to buzz.
5. **Daily Doubles:** hidden behind 1 clue in round 1 and 2 in round 2. Only the picker plays, and they wager first (up to their score, or the top value on the board if that's higher).
6. **Round 2 (Double Up):** every value doubles. The lowest score picks first.
7. **Final Showdown:** everyone with a positive score sees the category, wagers privately, then has 35 seconds to answer. Answers are revealed one by one, lowest score first.

### Fixing a call

Auto-judging is lenient, but if it gets one wrong, the captain (or anyone at the TV) can tap **Flip last ruling**. That swaps the result and fixes the score. In the final, each answer card has its own **flip** button on the TV.

### TV controls

The TV page has faint buttons in the bottom right (hover to see them) plus keyboard shortcuts:

| Key | Action |
| --- | --- |
| S | Start game |
| K | Skip the current clue |
| O | Flip the last ruling |
| N / Enter / Space | Continue |

You can also click a tile on the TV board to pick it. Click **Sound** in the bottom left once to turn on sound effects.

## Question packs

Each `.json` file in the `questions` folder is a pack. In the lobby, the captain (or anyone at the TV) taps packs to switch them on or off, and the game draws its categories from whatever's on. You need at least 12 categories switched on in total.

| Pack | Categories | On by default |
| --- | --- | --- |
| Classic Mix | 18 | Yes |
| General Knowledge | 34 | Yes |
| Movie Night | 14 | No |
| Totally 90s | 14 | No |
| Sports Fan | 14 | No |

Each game picks 12 different categories at random (6 per round) and one final clue from the packs that are on.

### Make your own pack

There's a starter file at `questions/templates/family.json` for a family or friends trivia night. Fill in your clues, move the file up into the `questions` folder, and restart the server. You can also copy any existing pack and edit it. Format:

```json
{
  "title": "Pack name shown in the lobby",
  "description": "Short description",
  "selected": false,
  "categories": [
    {
      "name": "Category Name",
      "clues": [
        { "q": "Easiest clue ($200)", "a": "Answer", "alt": ["other accepted answer"] },
        { "q": "...", "a": "..." },
        { "q": "...", "a": "..." },
        { "q": "...", "a": "..." },
        { "q": "Hardest clue ($1000)", "a": "..." }
      ]
    }
  ],
  "finals": [
    { "category": "Final Category", "q": "The final clue", "a": "Answer", "alt": [] }
  ]
}
```

`"selected": false` means the pack starts switched off in the lobby. Use `alt` for nicknames, last names, or other spellings you want to accept.

## Troubleshooting

- **Phones can't connect:** make sure they're on the same Wi-Fi as the computer (not cellular data or a guest network) and that your firewall allows Node. If the computer has several network adapters, the server prints the other addresses too; try those.
- **Different port:** `PORT=8080 node server.js` (on Windows PowerShell: `$env:PORT=8080; node server.js`).
- **Someone's phone locked or refreshed:** just reopen the link. They rejoin with the same name and score.
- **Max players:** 8.

## Credits

QR codes are generated by [qrcode-generator](https://github.com/kazuhikoarase/qrcode-generator) by Kazuhiko Arase (MIT license), bundled in `public/vendor`.
