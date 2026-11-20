# Effect repos

Reference code for advanced visual effects. Point Claude Code at the repo URL, name the
one effect you want, and adapt it on a throwaway branch. Check the licence, maintenance and
framework fit before pulling anything in.

| Repo | Use it for |
| --- | --- |
| [pmndrs/react-three-fiber](https://github.com/pmndrs/react-three-fiber) | 3D in React. Its examples gallery (docs.pmnd.rs) is the place to find a scene to adapt |
| [dashersw/liquid-glass-js](https://github.com/dashersw/liquid-glass-js) | Apple Liquid Glass style panels, buttons and nav. Plain JS, last updated mid 2025 |
| [ruucm/shadergradient](https://github.com/ruucm/shadergradient) | Moving mesh gradients for hero backgrounds. React, Framer and Figma; shape, colour and motion are configurable |
| [paper-design/liquid-logo](https://github.com/paper-design/liquid-logo) | A transparent PNG logo rendered as animated liquid metal. Built on Paper Shaders (`@paper-design/shaders`) |

Example prompt: "Turn my logo into animated liquid metal using
https://github.com/paper-design/liquid-logo".

Source: Cindy Zhu's reel, instagram.com/reel/DcxV37-CJOC.

Most of these effects animate continuously. If you avoid continuously repainting animations, keep them to one hero spot,
or stop them after a few seconds or when they scroll offscreen.
