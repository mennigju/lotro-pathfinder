-- Pathfinder.L: Texte auf Deutsch und Englisch. Pathfinder.Lang ("de"/"en")
-- setzt Main.lua nach der Client-Sprache oder /pf sprache.

Pathfinder = Pathfinder or {}

Pathfinder.Lang = Pathfinder.Lang or "de"

local Strings = {
    de = {
        -- Windows
        map = "Karte",
        list = "Liste",
        noRoute = "Keine Route",
        noRouteHint = "/pf hier oder /pf liste",
        routeFinished = "Route fertig!",
        otherRegion = "Andere Region",
        clickArrow = "Pfeil anklicken = Position",
        posAge = "Position vor %s s",
        noMapImage = "Kein Kartenbild fuer diese Route",
        noRouteSelected = "Keine Route gewaehlt",
        mapFinished = "Route fertig: %s/%s",
        mapNext = "Naechstes Ziel: %s  (%s/%s erledigt)",
        mapHover = "%s. %s  (%s)  Klick = erledigt an/aus",
        deedsTitle = "Pathfinder - Taten",
        deedsHint = "Haken = schon erledigt. Haken an der Tat = alle Ziele.",
        -- Chat
        loaded = "%s Routen geladen. /pf fuer Hilfe",
        version = "Version %s, ",
        routeSelected = "Route %s (%s/%s erledigt)",
        reached = "Erreicht: %s Ziel(e). %s/%s",
        routesHereHint = "Hier gibt es Routen: /pf hier",
        chatTicked = "%s Ziel(e) per Chat abgehakt. %s/%s",
        noMatches = "%s: keine Treffer",
        listHeader = "%s (waehlen mit /pf route <Nr>):",
        listMore = "... und %s weitere, Suche eingrenzen: /pf liste <Text>",
        routesHere = "Routen hier",
        routes = "Routen",
        posUnknown = "Position unbekannt: erst den Pfeil anklicken (%s)",
        routeNotFound = "Keine Route gefunden: %s",
        routeReset = "Route zurueckgesetzt",
        ticked = "Abgehakt: %s",
        radiusSet = "Radius %s m",
        ageSet = "Pfeil wird nach %s s grau",
        flipped = "Pfeil gespiegelt",
        notFlipped = "Pfeil normal",
        debugOn = "Debug an (Script.log, Zeilen mit %s)",
        debugOff = "Debug aus",
        langSet = "Sprache: Deutsch. Wirkt nach /plugins unload Pathfinder + load",
        shortHelp = "Pathfinder: Routen fuer Taten",
        help = {
            "Befehle:",
            "  /pf hier - Routen an deiner Position (vorher Pfeil anklicken)",
            "  /pf liste [Text] - Routen suchen, /pf route <Nr|Text> - waehlen",
            "  /pf weiter | zurueck | reset - Ziel ueberspringen, zurueck, Route neu",
            "  /pf karte | taten | pfeil - Fenster ein/aus (Taten: erledigte Ziele abhaken)",
            "  /pf erledigt - aktuelles Ziel abhaken (auch: Punkt auf der Karte anklicken)",
            "  /pf radius <m> - Abstand zum Abhaken (jetzt %RADIUS% m)",
            "  /pf alter <s> - Pfeil nach so vielen Sekunden grau (jetzt %AGE% s)",
            "  /pf drehen - Pfeil spiegeln, falls er falsch herum dreht",
            "  /pf sprache de|en - Sprache, /pf debug - Chat und Positionen ins Script.log",
            "  Pfeil anklicken = %POS%. Tipp: Pfeil auf eine Schnellleiste ziehen und auf eine Taste legen.",
        },
        commandHelp = "/pf hier | liste | route | weiter | zurueck | erledigt | reset | karte | taten | pfeil | radius | alter | drehen | sprache | debug",
    },
    en = {
        map = "Map",
        list = "List",
        noRoute = "No route",
        noRouteHint = "/pf here or /pf list",
        routeFinished = "Route finished!",
        otherRegion = "Other region",
        clickArrow = "Click arrow = position",
        posAge = "Position %s s ago",
        noMapImage = "No map image for this route",
        noRouteSelected = "No route selected",
        mapFinished = "Route finished: %s/%s",
        mapNext = "Next target: %s  (%s/%s done)",
        mapHover = "%s. %s  (%s)  click = toggle done",
        deedsTitle = "Pathfinder - Deeds",
        deedsHint = "Tick = already done. Tick on the deed = all targets.",
        loaded = "%s routes loaded. /pf for help",
        version = "Version %s, ",
        routeSelected = "Route %s (%s/%s done)",
        reached = "Reached: %s target(s). %s/%s",
        routesHereHint = "There are routes here: /pf here",
        chatTicked = "%s target(s) ticked off via chat. %s/%s",
        noMatches = "%s: no matches",
        listHeader = "%s (choose with /pf route <no>):",
        listMore = "... and %s more, narrow the search: /pf list <text>",
        routesHere = "Routes here",
        routes = "Routes",
        posUnknown = "Position unknown: click the arrow first (%s)",
        routeNotFound = "No route found: %s",
        routeReset = "Route reset",
        ticked = "Ticked off: %s",
        radiusSet = "Radius %s m",
        ageSet = "Arrow turns grey after %s s",
        flipped = "Arrow mirrored",
        notFlipped = "Arrow normal",
        debugOn = "Debug on (Script.log, lines starting with %s)",
        debugOff = "Debug off",
        langSet = "Language: English. Takes effect after /plugins unload Pathfinder + load",
        shortHelp = "Pathfinder: routes for deeds",
        help = {
            "Commands:",
            "  /pf here - routes at your position (click the arrow first)",
            "  /pf list [text] - search routes, /pf route <no|text> - choose one",
            "  /pf next | back | reset - skip target, go back, restart route",
            "  /pf map | deeds | arrow - toggle windows (deeds: tick off finished targets)",
            "  /pf done - tick off the current target (or click a point on the map)",
            "  /pf radius <m> - distance for ticking off (now %RADIUS% m)",
            "  /pf age <s> - arrow turns grey after this many seconds (now %AGE% s)",
            "  /pf flip - mirror the arrow if it turns the wrong way",
            "  /pf lang de|en - language, /pf debug - write chat and positions to Script.log",
            "  Click arrow = %POS%. Tip: drag the arrow onto a quickbar and bind a key to it.",
        },
        commandHelp = "/pf here | list | route | next | back | done | reset | map | deeds | arrow | radius | age | flip | lang | debug",
    },
}

-- Localized text; extra arguments are filled into %s
function Pathfinder.L(key, ...)
    local text = (Strings[Pathfinder.Lang] or Strings.en)[key] or Strings.de[key] or key
    if select("#", ...) > 0 then
        local args = { ... }
        for i = 1, #args do
            args[i] = tostring(args[i])
        end
        return string.format(text, unpack(args))
    end
    return text
end

-- Command words in both languages -> internal name
Pathfinder.COMMANDS = {
    here = "here", hier = "here",
    list = "list", liste = "list",
    route = "route",
    next = "next", weiter = "next",
    back = "back", zurueck = "back", ["zurück"] = "back",
    done = "done", erledigt = "done",
    reset = "reset",
    map = "map", karte = "map",
    deeds = "deeds", taten = "deeds",
    arrow = "arrow", pfeil = "arrow",
    radius = "radius",
    age = "age", alter = "age",
    flip = "flip", drehen = "flip",
    lang = "lang", sprache = "lang",
    debug = "debug",
}
