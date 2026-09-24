# Composes the final spec's comparison sheet from the renders in shots/ (today)
# and final/ (the spec). Run from the folder holding both, after the harness.
from montage_base import sheet_compare

sh, fn = "shots/", "final/"
sheet_compare("Errol's console: today and the converged layout",
              "The capsule and its ends stay; words move where there is room, and the box becomes a status panel while the relay owns it",
              ["Today", "Converged layout"],
              [("Ready to start", [sh + "03-compose-connected-topic.png", fn + "01-ready.png"]),
               ("ChatGPT has two conversations open", [sh + "01-compose-several-conversations.png", fn + "02-choose-destination.png"]),
               ("Running, ChatGPT replying at turn 5", [sh + "08-running-mid.png", fn + "04-running.png"]),
               ("Paused to write a note", [sh + "09-paused-writing-note.png", fn + "06-paused.png"]),
               ("Finished", [sh + "12-finished.png", fn + "09-finished-complete.png"])],
              "compare-today-final.png")
