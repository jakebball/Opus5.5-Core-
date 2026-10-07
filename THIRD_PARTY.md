# Third-party software

## Fetched or installed by each user (not in this repository)

| Project | Used for | How it arrives |
| --- | --- | --- |
| [robloxMeshTools](https://github.com/MrChickenRocket/robloxMeshTools) by MrChickenRocket | `MeshKit` (every `/blenderassets` push) and `/importmeshtools` | `install.ps1` / `install.sh` download commit `01b74d5c25f799b7622b9a74e57266a83398bcfb` from upstream. The upstream repository carries no license file, so it is not redistributed here. |
| [robloxstudio-mcp](https://github.com/boshyxd/robloxstudio-mcp) (archived) / [fork](https://github.com/Chrrxs/robloxstudio-mcp) | the Studio MCP plugin and server | installed by each user from its releases and npm |
| [Blender](https://www.blender.org) (GPL) | headless builds and renders | installed by each user |
| [Node.js](https://nodejs.org), [Rojo](https://rojo.space) (MPL-2.0) | the skill scripts; rebuilding the baseplate | installed by each user |

## Bundled in the baseplate (`baseplate/src/ServerScriptService/Runner/Shared/Generic/`)

These community libraries ship inside the Runner framework. Several copies lost their header comments to the
framework's comment rule, so their credit and license live here. **Before publishing, check each upstream license and
keep its notice with the code** (MIT and Apache-2.0 both require the notice to travel with copies).

| Module | Project and author | License as stated upstream |
| --- | --- | --- |
| `Profilestore` | [ProfileStore](https://github.com/MadStudioRoblox/ProfileStore), loleris (MAD STUDIO) | see upstream |
| `Promise` | [roblox-lua-promise](https://github.com/evaera/roblox-lua-promise), evaera | MIT (verify) |
| `GoodSignal` | [GoodSignal](https://devforum.roblox.com/t/lua-signal-class-comparison-optimal-goodsignal-class/1387063), stravant | MIT (verify) |
| `Trove` | [RbxUtil Trove](https://github.com/Sleitnick/RbxUtil), Sleitnick | MIT (verify) |
| `CameraShake` | [RbxCameraShaker](https://github.com/Sleitnick/RbxCameraShaker), Sleitnick | MIT (verify) |
| `Spr` | [spr](https://github.com/Fraktality/spr), Fractality | MIT (notice kept in the file) |
| `Icon` | [TopbarPlus](https://github.com/1ForeverHD/TopbarPlus), ForeverHD | MIT (verify) |
| `Zone` | [ZonePlus](https://github.com/1ForeverHD/ZonePlus), ForeverHD | MIT (verify) |
| `Octree` | [Nevermore Octree](https://github.com/Quenty/NevermoreEngine), Quenty | MIT (verify) |
| `WindShake`, `WindLines` | [WindShake / WindLines](https://github.com/boatbomber), boatbomber | MPL-2.0 / MIT (verify) |
| `Rain` | Rain module, buildthomas | Apache-2.0 (notice kept in the file) |
| `EmitModule` | EmitModule | its own license, kept as a string in the file |
| `BehaviorTreeCreator` | [BTrees Visual Editor](https://devforum.roblox.com/t/btrees-visual-editor-v2-0/461015), tyridge77 and defaultio | see upstream (credit kept in the file) |

Everything else in the baseplate (the Runner framework, `EntityStore`, `BaseClass`, the Generic components, the
AdminSystem and the skills in `skills/`) is the team's own work.
