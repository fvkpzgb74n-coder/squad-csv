# squad-csv

**Lineup** is a native iPhone app (SwiftUI, iOS 17+) for managing a football squad and building matchday lineups. You can bring the squad in from a CSV file, or add players by hand.

## Features

- **Squad management**: add, edit and delete players. Each player has a name, shirt number, positions (in order of preference), availability and notes. Players are grouped by position, and you can search the list. Swipe a player to mark them unavailable.
- **CSV import/export**: import a squad from any spreadsheet export, then merge it with the current squad or replace it. You can also export the squad to CSV.
- **Lineup builder**: shows your formation on a pitch.
  - Tap a position to pick a player. Players who play that position are listed first, and unavailable or already-picked players are flagged.
  - Picking a player who is already on the pitch swaps the two players. Picking a substitute swaps them with the player in that position.
  - Drag players to fine-tune where they stand.
  - Pick a captain, manage the substitutes' bench, and see who hasn't been selected.
  - **Auto-fill** puts the best-suited available players into the empty positions.
  - When you switch formation, players keep matching roles where possible, and anyone left over goes to the bench.
- **Formations**:
  - 11-a-side: 4-4-2, 4-3-3, 4-2-3-1, 4-1-4-1, 4-4-1-1, 3-5-2, 3-4-3, 5-3-2, 5-4-1
  - 9-a-side: 3-3-2, 3-2-3
  - 7-a-side: 2-3-1, 3-2-1
  - 5-a-side: 2-2, 1-2-1
- **Sharing**: share a lineup as an image of the pitch along with a text team sheet, or copy the team sheet as text.
- Everything is saved on the device automatically, as JSON in the app's Documents folder.

## Running it

### On an iPad (no Mac needed)

1. Install **Swift Playgrounds** (free) from the App Store.
2. Download this project as a ZIP and unzip it in the **Files** app.
3. Tap **Lineup.swiftpm**. It opens in Swift Playgrounds.
4. Tap ▶️ to run the app. To install it on your device, use the app's menu and choose to install it.

### On a Mac

Open `SquadCSV.xcodeproj` (or `Lineup.swiftpm`) in **Xcode 16 or later**, pick an iPhone simulator, and press ⌘R. To run it on your own iPhone, choose your team under *Signing & Capabilities*. You may need to change the bundle identifier from `com.example.SquadCSV`.

Both open the same source code in `Lineup.swiftpm/Sources`.

To try the app quickly, tap **Load Sample Squad** on the Squad tab, or import `SampleData/sample-squad.csv`.

Run the unit tests in Xcode with ⌘U. They cover CSV parsing, import/export round-trips and the lineup logic. Swift Playgrounds doesn't run unit tests.

## CSV format

```csv
Name,Number,Positions,Available,Notes
Sam Okafor,1,GK,Yes,
Leo Varga,2,RB/RWB,Yes,
Elliot Price,20,CM,No,Hamstring
```

- Column headers can be in any order and are case-insensitive. The importer recognises common alternatives, such as `Player`, `#`, `No`, `Pos`, `Position`, `Status`, and `First Name` + `Last Name` columns.
- Separate positions with `/`, `|`, spaces or commas (commas only inside quotes). The first position listed is the player's main position. Accepted codes are `GK LB CB RB LWB RWB CDM CM CAM LM RM LW RW CF ST`, plus words like `Goalkeeper`, `Defender`, `Midfielder`, `Striker`, `DM` and `AM`.
- `Available` accepts `No`, `False`, `0`, `Injured`, `Suspended` or `Out` to mark a player unavailable. Anything else, including a blank, counts as available.
- Comma, semicolon and tab-separated files all work, and the importer copes with Excel's UTF-8 BOM.
- Files without a header row are read as `Name, Number, Positions`.

## Project layout

```
Lineup.swiftpm/   Swift Playgrounds app package (Package.swift)
  Sources/        All app source code and assets
    App/          App entry point and tab view
    Models/        Player, Position, Formation, Lineup (pure Swift, unit-tested)
    Store/         SquadStore – observable state + JSON persistence
    CSV/           CSV parser/writer and squad import/export
    Views/Squad/    Squad list and player editor
    Views/Lineups/  Lineup list, editor, player picker, share card
    Views/Components/ Pitch drawing, player tokens and badges
SquadCSV.xcodeproj  Xcode project (builds the same sources)
SquadCSVTests/    XCTest unit tests
SampleData/       Example squad CSV
```
