Pathfinder - routes for LOTRO deeds / Routen fuer LOTRO-Taten
================================================================

ENGLISH

Pathfinder guides you along a precomputed short route to the targets of
explorer and lore deeds: an arrow points to the next target, a map shows the
route, a list lets you tick off what you have already done. Below the arrow:
distance to the target and the way left on the route.

Install: unpack the ZIP into
  Documents\The Lord of the Rings Online\Plugins\
so that the folder Plugins\Pathfinder exists. In game: /plugins load Pathfinder

Use:
  - Click the arrow: it runs /loc and updates your position. Tip: drag the
    arrow onto a quickbar and bind a key to that slot.
  - /pf here       routes at your position
  - /pf list bree  search routes, /pf route 1  choose one; the arrow starts
    at the open target nearest to you
  - /pf reroute    new order of the open targets from where you stand
                   (/pf reset brings back the original order)
  - "List" button  tick off targets and whole deeds you already have
  - "Map" button   map with the route; click a point to toggle it
  - /pf            all commands

Why no automatic position? The plugin API has no player position and plugins
may not run commands on their own, so /loc needs your click or key press.
Single landmark discoveries don't show up in chat, so targets are ticked off
by position (when you click near them or pass them between two clicks) or
when the game reports the whole deed as completed.

Language: follows the game client (German or English), /pf lang en|de
switches it.


DEUTSCH

Pathfinder fuehrt dich auf einer vorberechneten kurzen Route zu den Zielen
von Erkundungs- und Wissens-Taten: ein Pfeil zeigt zum naechsten Ziel, eine
Karte zeigt die Route, in einer Liste hakst du ab, was du schon hast. Unter
dem Pfeil: Entfernung zum Ziel und der restliche Weg der Route.

Installation: ZIP entpacken nach
  Dokumente\The Lord of the Rings Online\Plugins\
so dass es den Ordner Plugins\Pathfinder gibt. Im Spiel: /plugins load Pathfinder

Bedienung:
  - Pfeil anklicken: fuehrt /pos aus und aktualisiert die Position. Tipp: den
    Pfeil auf eine Schnellleiste ziehen und den Platz auf eine Taste legen.
  - /pf hier        Routen an deiner Position
  - /pf liste bree  Routen suchen, /pf route 1  eine waehlen; der Pfeil
    beginnt beim offenen Ziel, das dir am naechsten ist
  - /pf neu         Reihenfolge der offenen Ziele ab deinem Standort neu
                    berechnen (/pf reset stellt die urspruengliche wieder her)
  - Knopf "Liste"   erledigte Ziele und ganze Taten abhaken
  - Knopf "Karte"   Karte mit Route; Punkt anklicken = erledigt an/aus
  - /pf             alle Befehle

Warum keine automatische Position? Die Plugin-Schnittstelle kennt keine
Spielerposition, und Plugins duerfen keine Befehle selbst ausfuehren. /pos
braucht deshalb deinen Klick oder Tastendruck. Einzelne entdeckte Orte
erscheinen nicht im Chat, deshalb werden Ziele ueber die Position abgehakt
(Klick in der Naehe oder vorbeigelaufen zwischen zwei Klicks) oder wenn das
Spiel die ganze Tat als abgeschlossen meldet.

Sprache: richtet sich nach dem Spiel-Client (Deutsch oder Englisch),
/pf sprache de|en stellt um.


LICENSE / LIZENZ

Code: MIT License, Copyright (c) 2026 jmennig (see LICENSE.txt).
The map images and deed data are game content and not covered by the MIT
license. / Kartenbilder und Tat-Daten sind Spielinhalte und fallen nicht
unter die MIT-Lizenz.


CREDITS

Deed coordinates, names and map images: LotroCompanion
(github.com/LotroCompanion lotro-data and lotro-maps-db), originally from
the game data of The Lord of the Rings Online (Standing Stone Games).
/loc conversion formula as in the Waypoint plugin by Lunarwater.
