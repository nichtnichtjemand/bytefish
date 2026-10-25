
"use strict";

const CONFIG = {
    username: "Bytefish",
    lichessUrl: "https://lichess.org",
    refreshInterval: 3000,
    connectTimeout: 15000
};

const elements = {
    board: document.getElementById("live-board"),
    status: document.getElementById("live-status"),
    players: document.getElementById("live-players"),
    details: document.getElementById("live-details"),
    moves: document.getElementById("live-moves"),
    link: document.getElementById("live-link")
};

let board = null;
let stopped = false;
let generation = 0;
let activeController = null;
let retryTimer = null;
let currentGameId = null;
let currentFen = null;
let moveHistory = [];

// --------------------------------------------------
// Initialization
// --------------------------------------------------

function initialize() {
    if (!elements.board) {
        console.error("Live board element not found.");
        return;
    }

    if (typeof window.Chessboard !== "function") {
        showError("Chessboard.js could not be loaded.");
        return;
    }

    if (typeof window.Chess !== "function") {
        showError("chess.js could not be loaded.");
        return;
    }

    board = window.Chessboard("live-board", {
        position: "start",
        showNotation: true,
        draggable: false,
        pieceTheme:
            "https://chessboardjs.com/img/chesspieces/wikipedia/{piece}.png"
    });

    setupBoardAnnotations();


    window.addEventListener("resize", () => board?.resize());

    discoverGame();
}

// --------------------------------------------------
// Helpers
// --------------------------------------------------

function setStatus(message) {
    if (elements.status) {
        elements.status.textContent = message;
    }
}

function showError(message) {
    setStatus(message);
    console.error(message);
}

function getPlayerName(player, fallback) {
    return player?.user?.name ?? player?.name ?? fallback;
}

function getStatusName(status) {
    return typeof status === "string"
        ? status
        : status?.name ?? "";
}

function stopCurrentRequest() {
    activeController?.abort();
    activeController = null;
}

function scheduleRetry(delay = CONFIG.refreshInterval) {
    if (stopped) return;

    clearTimeout(retryTimer);
    retryTimer = setTimeout(discoverGame, delay);
}

// --------------------------------------------------
// Find the current game
// --------------------------------------------------

async function discoverGame() {
    if (stopped) return;

    const myGeneration = ++generation;

    stopCurrentRequest();

    const controller = new AbortController();
    activeController = controller;

    setStatus("Checking Lichess...");

    try {
        const url =
            `${CONFIG.lichessUrl}/api/user/` +
            `${encodeURIComponent(CONFIG.username)}` +
            `/current-game?moves=false&tags=true`;

        const response = await fetch(url, {
            headers: {
                Accept: "application/x-chess-pgn"
            },
            cache: "no-store",
            signal: controller.signal
        });

        if (stopped || myGeneration !== generation) return;

        // Lichess can return 404 when no current game exists.
        if (response.status === 404) {
            showNoGame();
            scheduleRetry();
            return;
        }

        if (!response.ok) {
            throw new Error(
                `Current-game request failed: HTTP ${response.status}`
            );
        }

        const pgn = await response.text();


        const match = pgn.match(
            /^\[GameId\s+"([A-Za-z0-9_-]+)"\]/mi
        );

        if (!match) {
            console.warn("Could not extract game ID from PGN:", pgn);
            setStatus("Could not determine the game ID.");
            scheduleRetry();
            return;
        }

        const gameId = match[1];

        console.log("Detected Lichess game ID:", gameId);



        console.log("Detected Lichess game ID:", gameId);

        if (gameId === currentGameId) {
            // The current stream already handles this game.
            return;
        }

        await streamGame(gameId, myGeneration);

        if (!stopped && myGeneration === generation) {
            scheduleRetry(1000);
        }
    } catch (error) {
        if (
            stopped ||
            myGeneration !== generation ||
            error.name === "AbortError"
        ) {
            return;
        }

        console.error("Game discovery failed:", error);
        setStatus(`Connection error: ${error.message}`);
        scheduleRetry(5000);
    } finally {
        if (activeController === controller) {
            activeController = null;
        }
    }
}

// --------------------------------------------------
// Game information
// --------------------------------------------------

function renderGameInfo(game) {
    const white = getPlayerName(game.players?.white, "White");
    const black = getPlayerName(game.players?.black, "Black");

    elements.players.textContent = `${white} vs. ${black}`;

    const speed = game.speed
        ? game.speed.charAt(0).toUpperCase() + game.speed.slice(1)
        : "";

    const rated = game.rated ? "Rated" : "Casual";

    elements.details.textContent = [speed, rated]
        .filter(Boolean)
        .join(" · ");

    elements.link.href = `${CONFIG.lichessUrl}/${encodeURIComponent(game.id)}`;
    elements.link.textContent = "View game on Lichess →";
}

function showNoGame() {
    currentGameId = null;
    currentFen = null;
    moveHistory = [];

    setStatus("Bytefish is not playing right now.");

    elements.players.textContent = "No active game";
    elements.details.textContent = "";
    elements.moves.replaceChildren();

    elements.link.href =
        `${CONFIG.lichessUrl}/@/${encodeURIComponent(CONFIG.username)}`;

    elements.link.textContent = "View Bytefish on Lichess →";

    board?.position("start", false);
}

// --------------------------------------------------
// Move list
// --------------------------------------------------

function renderMoves() {
    const fragment = document.createDocumentFragment();

    moveHistory.forEach((move, index) => {
        const item = document.createElement("li");

        item.textContent =
            `${Math.floor(index / 2) + 1}. ` +
            (index % 2 === 0 ? move : "");

        if (index % 2 === 1) {
            item.textContent = move;
        }

        fragment.appendChild(item);
    });

    elements.moves.replaceChildren(fragment);
}

function uciToSan(uci) {
    if (!/^[a-h][1-8][a-h][1-8][qrbn]?$/i.test(uci)) {
        return uci;
    }

    const move = {
        from: uci.slice(0, 2),
        to: uci.slice(2, 4)
    };

    if (uci.length === 5) {
        move.promotion = uci[4].toLowerCase();
    }

    return move;
}

// --------------------------------------------------
// Stream a game
// --------------------------------------------------

async function streamGame(gameId, myGeneration) {
    const controller = new AbortController();
    activeController = controller;

    currentGameId = gameId;
    currentFen = null;
    moveHistory = [];

    const chess = new window.Chess();
    let receivedFirstMessage = false;
    let buffer = "";

    setStatus("Connecting to live game...");

    elements.link.href = `${CONFIG.lichessUrl}/${encodeURIComponent(gameId)}`;
    elements.link.textContent = "View game on Lichess →";
    elements.moves.replaceChildren();

    const timeoutId = setTimeout(() => {
        if (!receivedFirstMessage) {
            controller.abort();
        }
    }, CONFIG.connectTimeout);

    try {
        const response = await fetch(
            `${CONFIG.lichessUrl}/api/stream/game/${encodeURIComponent(gameId)}`,
            {
                headers: {
                    Accept: "application/x-ndjson"
                },
                cache: "no-store",
                signal: controller.signal
            }
        );

        if (!response.ok || !response.body) {
            throw new Error(`Game stream returned HTTP ${response.status}`);
        }

        const reader = response.body.getReader();
        const decoder = new TextDecoder();

        try {
            while (!stopped && myGeneration === generation) {
                const { value, done } = await reader.read();

                if (done) break;

                buffer += decoder.decode(value, { stream: true });

                const lines = buffer.split("\n");
                buffer = lines.pop() ?? "";

                for (const line of lines) {
                    if (!line.trim()) continue;

                    let event;

                    try {
                        event = JSON.parse(line);
                    } catch (error) {
                        console.warn("Invalid stream JSON:", error);
                        continue;
                    }

                    receivedFirstMessage = true;
                    clearTimeout(timeoutId);

                    if (stopped || myGeneration !== generation) {
                        return;
                    }

                    // First message: game metadata.
                    if (event.players) {
                        event.id ??= gameId;
                        renderGameInfo(event);
                    }

                    // Subsequent messages contain FEN and optional "lm".
                    if (event.fen) {
                        if (event.lm && currentFen) {
                            try {
                                chess.load(currentFen);

                                const move = chess.move(
                                    uciToSan(event.lm)
                                );

                                moveHistory.push(
                                    move?.san ?? event.lm
                                );

                                renderMoves();
                            } catch (error) {
                                console.warn(
                                    "Could not process move:",
                                    event.lm,
                                    error
                                );
                            }
                        }

                        currentFen = event.fen;
                        board.position(event.fen, true);
                        setStatus("Live game");
                    }

                    const status = getStatusName(event.status);

                    if (status && status !== "started") {
                        setStatus(`Game finished: ${status}`);
                        return;
                    }
                }
            }
        } finally {
            reader.releaseLock();
        }

        if (!stopped && myGeneration === generation) {
            setStatus("Stream ended. Reconnecting...");
        }
    } catch (error) {
        if (stopped || myGeneration !== generation) return;

        if (error.name === "AbortError") {
            setStatus("Connection timed out. Reconnecting...");
        } else {
            console.error("Live stream failed:", error);
            setStatus(`Stream error: ${error.message}`);
        }
    } finally {
        clearTimeout(timeoutId);

        if (activeController === controller) {
            activeController = null;
        }
    }
}

// --------------------------------------------------
// Start and cleanup
// --------------------------------------------------

if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initialize, {
        once: true
    });
} else {
    initialize();
}

window.addEventListener("pagehide", () => {
    stopped = true;
    generation++;

    clearTimeout(retryTimer);
    stopCurrentRequest();
});


function setupBoardAnnotations() {
    const container = elements.board;

    if (!container || container.dataset.annotationsReady) return;
    container.dataset.annotationsReady = "true";

    container.style.position = "relative";

    const svgNS = "http://www.w3.org/2000/svg";
    const svg = document.createElementNS(svgNS, "svg");

    Object.assign(svg.style, {
        position: "absolute",
        inset: "0",
        width: "100%",
        height: "100%",
        overflow: "hidden",
        pointerEvents: "none",
        zIndex: "10"
    });

    svg.setAttribute("viewBox", "0 0 800 800");
    svg.setAttribute("preserveAspectRatio", "none");
    const defs = document.createElementNS(svgNS, "defs");
    const marker = document.createElementNS(svgNS, "marker");

    marker.setAttribute("id", "bytefish-arrowhead");
    marker.setAttribute("markerWidth", "50");
    marker.setAttribute("markerHeight", "40");
    marker.setAttribute("viewBox", "0 0 50 40");
    marker.setAttribute("refX", "48");
    marker.setAttribute("refY", "20");
    marker.setAttribute("orient", "auto");
    marker.setAttribute("markerUnits", "userSpaceOnUse");

    const tip = document.createElementNS(svgNS, "path");
    tip.setAttribute("d", "M 2 2 L 48 20 L 2 38 Z");
    tip.setAttribute("fill", "#e7b94f");

    marker.appendChild(tip);
    defs.appendChild(marker);
    svg.appendChild(defs);
    container.appendChild(svg);

    let startSquare = null;
    let preview = null;

    function getSquare(event) {
        const rect = container.getBoundingClientRect();

        const x = (event.clientX - rect.left) / rect.width;
        const y = (event.clientY - rect.top) / rect.height;

        if (x < 0 || x > 1 || y < 0 || y > 1) return null;

        const file = Math.min(7, Math.floor(x * 8));
        const rank = 8 - Math.min(7, Math.floor(y * 8));

        return {
            name: "abcdefgh"[file] + rank,
            x: (file + 0.5) * 100,
            y: (8 - rank + 0.5) * 100
        };
    }
    function createArrow(from, to, isPreview = false) {
        const group = document.createElementNS(svgNS, "g");

        const color = "#e7b94f";
        const dx = to.x - from.x;
        const dy = to.y - from.y;
        const length = Math.hypot(dx, dy);

        if (length === 0) return group;

        const ux = dx / length;
        const uy = dy / length;

        // Größe der Pfeilspitze
        const headLength = 40;
        const headWidth = 25;

        // Basis des Pfeilkopfes
        const baseX = to.x - ux * headLength;
        const baseY = to.y - uy * headLength;

        // Senkrechter Vektor für die Breite des Dreiecks
        const px = -uy * headWidth;
        const py = ux * headWidth;

        // Linie endet exakt an der Basis des Pfeilkopfes
        const line = document.createElementNS(svgNS, "line");
        line.setAttribute("x1", from.x);
        line.setAttribute("y1", from.y);
        line.setAttribute("x2", baseX);
        line.setAttribute("y2", baseY);
        line.setAttribute("stroke", color);
        line.setAttribute("stroke-width", "20");
        line.setAttribute("stroke-linecap", "round");

        // Pfeilspitze mit der Spitze exakt auf to.x / to.y
        const head = document.createElementNS(svgNS, "polygon");
        head.setAttribute(
            "points",
            `${to.x},${to.y} ` +
            `${baseX + px},${baseY + py} ` +
            `${baseX - px},${baseY - py}`
        );
        head.setAttribute("fill", color);

        group.appendChild(line);
        group.appendChild(head);

        if (isPreview) {
            group.setAttribute("opacity", "0.65");
            group.dataset.preview = "true";
        } else {
            group.dataset.annotationKey =
                `arrow:${from.name}-${to.name}`;
        }

        return group;
    }

    function createCircle(square) {
        const circle = document.createElementNS(svgNS, "circle");

        circle.setAttribute("cx", square.x);
        circle.setAttribute("cy", square.y);
        circle.setAttribute("r", "39");
        circle.setAttribute("fill", "none");
        circle.setAttribute("stroke", "#e7b94f");
        circle.setAttribute("stroke-width", "10");

        return circle;
    }

    container.addEventListener("contextmenu", event => {
        if (event.target.closest("#live-board")) {
            event.preventDefault();
        }
    });

    container.addEventListener("pointerdown", event => {
        if (event.button === 2) {
            event.preventDefault();
            startSquare = getSquare(event);
            preview?.remove();
            preview = null;
        }
        else if (event.button === 0) {
            svg.querySelectorAll("[data-annotation-key]")
                .forEach(el => el.remove());

            preview?.remove();
            preview = null;
            startSquare = null;
        }
    });

    container.addEventListener("pointermove", event => {
        if (!startSquare || !(event.buttons & 2)) return;

        const target = getSquare(event);
        if (!target) return;

        preview?.remove();
        preview = createArrow(startSquare, target, true);
        preview.dataset.preview = "true";
        svg.appendChild(preview);
    });
    container.addEventListener("pointerup", event => {
        if (event.button !== 2 || !startSquare) return;

        const from = startSquare;
        const to = getSquare(event);

        preview?.remove();
        preview = null;
        startSquare = null;

        if (!to) return;

        // Rechtsklick auf dasselbe Feld: Kreis umschalten
        if (from.name === to.name) {
            const key = `circle:${from.name}`;
            const existing = svg.querySelector(
                `[data-annotation-key="${key}"]`
            );

            if (existing) {
                existing.remove();
            } else {
                const circle = createCircle(from);
                circle.dataset.annotationKey = key;
                svg.appendChild(circle);
            }

            return;
        }

        // Pfeil bereits vorhanden? Dann entfernen.
        const key = `arrow:${from.name}-${to.name}`;
        const existing = svg.querySelector(
            `[data-annotation-key="${key}"]`
        );

        if (existing) {
            existing.remove();
        } else {
            svg.appendChild(createArrow(from, to));
        }
    });

}
