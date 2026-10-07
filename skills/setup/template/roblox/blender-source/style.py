"""{{NAME}} palette: the only place asset colours are defined (features/art-direction.md, Project Art Style).

Asset scripts import it and pick colours by name: `from style import PALETTE` then `colour=PALETTE["Wood"]`.
A new colour is added here first, never inline in one asset.
"""

PALETTE = {}
