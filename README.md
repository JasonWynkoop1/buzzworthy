# Buzzworthy

A party trivia game. The board runs on a TV and everyone buzzes in from their phone.

| Folder | What it is | How it ships |
| --- | --- | --- |
| `web/` | The website: TV page (`index.html`) and phone page (`play.html`). Live at https://buzzworthy-one.vercel.app | Vercel deploys `main` automatically (see `vercel.json`). Other branches get preview links. |
| `tvos/` | Native Apple TV app. Runs the same game engine as the website. | GitHub Actions builds it, runs a simulator game, and uploads to TestFlight on pushes to `main`. |
| `offline/` | Backup version that runs on a PC on home Wi-Fi with `node server.js` (or `Start Buzzworthy.bat`). | Copy the folder to the PC. |

## Questions

- House packs are JSON files in `web/questions/` (listed in `index.json`). The Apple TV app downloads them from the website at the start of each room.
- `web/archive.js` loads real TV quiz-show boards for each new room from a fan-made public clue archive (one random season per room) and splits them into topic packs. The clues are fetched at play time and are not stored in this repo.

## Game engine

`web/engine/` (`game.js`, `rules.js`, `judge.js`) and `web/archive.js` are shared. The Apple TV app has copies in `tvos/BuzzworthyTV/Engine/`, so change both when you change one.

## Apple TV builds

- `.github/workflows/tvos.yml`: build check, phone protocol test, and a simulator game with screenshots (download them from the run's Artifacts). Use **Run workflow** to run it on demand.
- `.github/workflows/testflight.yml`: signs and uploads to TestFlight. Needs the `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8` repo secrets. Bumping `tvos/refresh.txt` forces a new build (TestFlight builds expire after 90 days).

See `tvos/README.md` for more.
