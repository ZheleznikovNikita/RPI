# AI Text RPG Vision Notes

This project is a Ruby on Rails web game prototype.

Current direction:

- Core stack: Ruby on Rails.
- Secondary languages/tools are acceptable only when Ruby/Rails is not a good fit for a specific part.
- Website structure starts with a main menu: start game, settings, registration, authorization.
- Visual tone: milky coffee palette, warm parchment surfaces, translucent panels.
- Game UI target:
  - HP and stamina bars in the top-left corner.
  - Inventory and profile buttons in the top-right corner.
  - A translucent lower text panel for narration and player input.
  - Player text input will later be sent to an AI API.
  - AI response should come back as JSON and be rendered for the player.
  - A separate request should generate a scene image.
  - Database should store story summaries/memory so the plot persists between turns and sessions.

First prototype scope:

- Rails application shell.
- Main menu.
- Game screen placeholder.
- Authorization and registration screens.
- Realtime UI Lab for quick browser-side visual tuning.