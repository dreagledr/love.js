Love.js for LÖVE v11.5
============
Basically trying to adapt [love.js](https://github.com/TannerRogalsky/love.js) to the latest and greatest versions of LÖVE and Emscripten.

This is a fork of [Davidobot/love.js](https://github.com/Davidobot/love.js). On top of the
upstream tooling it adds an asynchronous **HTTP module** and ships an
[example](sample/) that demonstrates it. There is no JavaScript bridge and no
`eval`: the old console-based trick is gone — talk to the network from Lua
instead.

## What this fork adds

* A Lua module named `http`, built on the [Emscripten Fetch API](https://emscripten.org/docs/api_reference/fetch.html)
  (`emscripten_fetch`). Async, with real status codes, headers and bodies:

  ```lua
  local http = require("http")

  http.request{
      url = "/api/random",
      method = "GET",
      headers = { ["Accept"] = "application/json" },
      data = nil,
      timeout = 10,
      withCredentials = false,
      onSuccess = function(res) end, -- { status, statusText, body, headers }
      onError = function(err) end,   -- { status, statusText, body, headers, message }
  }

  -- once per frame:
  http.poll()
  ```

  The module lives in [dreagledr/love](https://github.com/dreagledr/love)
  (`src/libraries/emfetch/emfetch.cpp`, branch `emscripten-fetch`), so the engine
  binaries committed here already contain it.

* The [`sample/`](sample/) directory: the sources of a small game that calls a
  [bun](https://bun.sh) dev server and prints whatever it gets back, plus a
  one-command way to run it (`bun run sample`).

## Quickstart
```
bun install
bun run sample
```

That packs `sample/game/`, builds the web bundle and serves it with the right
headers on <http://localhost:8080>. See [sample/readme.md](sample/readme.md) for
the details and the desktop instructions.

## Installation
This fork is **not published to npm** — run it from a checkout:

```
git clone https://github.com/dreagledr/love.js.git
cd love.js
npm install
```

(The `love.js` package on npm is [Davidobot's](https://github.com/Davidobot/love.js);
it does not have the `http` module this fork adds.)

## Usage
Run the CLI straight from the checkout:
```
node index.js [options] <input> <output>
```
or, if you have [bun](https://bun.sh):
```
bun index.js [options] <input> <output>
```

`<input>` can either be a folder or a `.love` file.
`<output>` is a folder that will hold debug and release web pages.

## Options:
```
-h, --help            output usage information
-V, --version         output the version number
-t, --title <string>  specify game name
-m, --memory [bytes]  how much memory your game will require [16777216]
-c, --compatibility   specify flag to use compatibility version
```

### Test it
1. Run a web server (while `cd`-ed into the `<output>` folder):
   - eg: `python -m http.server 8000`
2. Open `localhost:8000` in the browser of your choice.

For the release build the server also has to send the two headers below, otherwise
you will get `SharedArrayBuffer is not defined`. `sample/dev.ts` does this for you.

## Notes
1. Compatibility version (`-c`) should work with most browsers. The difference is that pthreads aren't used. This results in *dodgy audio*. 
2. The normal version works in the latest Chrome and should work with the latest Firefox version. 

The normal version can throw `Uncaught ReferenceError: SharedArrayBuffer is not defined`. Fix is discussed [here](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/SharedArrayBuffer#Security_requirements). TL;DR 
Enable the following HTML reponse headers on the website you're hosting your project on:
```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```
> If you want to publish your game on one of the game hosting platforms, like [itch.io](https://itch.io/) for example:
> - if they include these headers, use the standard version
> - if they don't, use the compatibility mode instead (`-c`)
> 
> On itch.io, they are disabled by default, but they provide experimental support for it. Read more about this [here](https://itch.io/t/2025776/experimental-sharedarraybuffer-support).

3. Memory is now dynamically resized even with pthreads thanks to [this](https://github.com/emscripten-core/emscripten/pull/8365). Still needs a large-enough initial memory until I figure out how to properly wait for the memory to be sized-up before initialising all the file-system stuff (pointers [here](https://emscripten.org/docs/getting_started/FAQ.html#how-can-i-tell-when-the-page-is-fully-loaded-and-it-is-safe-to-call-compiled-functions)).
4. Shaders work (check out 3D demo), but require stricter type-checking. _The OpenGL ES Shading Language is type safe. There are no implicit conversions between types_ ([source](https://www.khronos.org/registry/OpenGL/specs/es/3.2/GLSL_ES_Specification_3.20.pdf)). So something like
```GLSL
vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords)
{
    vec4 texturecolor = Texel(tex, texture_coords);
    return texturecolor * color / 2;
}
```
**won't** work, but changing line 4 to the code below will make everything run just fine:
```GLSL
return texturecolor * color / 2.0;
```

5. If you use `love.mouse.setGrabbed` or `love.mouse.setRelative`, the user needs to click on the canvas to "lock" the mouse.

6. Use `love.filesystem.getInfo(file_name)` before trying to read a potentially non-existent file. 

7. If you use a depth buffer, add the following line: `t.window.depth = 16` to your `config.lua` file to make sure normals aren't inverted in Firefox.

8. For HTTP requests use the `http` module above. Do not reintroduce the old
   console/`eval` JavaScript bridge: `HTTP` from Lua is what the engine supports
   now, and it works without a sandbox escape.

## Building

The binaries in `src/compat` and `src/release` are prebuilt and committed — normal
use never rebuilds them. If you change the engine you need a
[megasource](https://github.com/dreagledr/megasource/tree/emscripten-fetch) checkout
(with its `libs/love` submodule) and **emsdk 2.0.0** + **Ninja**.

emsdk 2.0.0 is not negotiable: newer versions removed `getMemory`, which the 11.5
tree still uses.

### Any OS, via Docker

`Dockerfile` bakes in everything the build needs — emsdk 2.0.0, Ninja, a modern
CMake and the engine sources (megasource with its `libs/love` submodule):

```
docker build -t lovejs-build .
docker run --rm -v "$PWD:/work" lovejs-build ./build_lovejs.sh
```

That is all: `EMSDK` and `MEGASOURCE` point at the baked-in copies. The artifacts
land in `src/compat` and `src/release`.

Add `--targets compat` (or `release`) to build just one, and `--clean` after
switching toolchains, since the build directory is shared with `/work`.

To build against a different branch or your own checkout:

```
docker build --build-arg MEGASOURCE_REF=<branch|tag> -t lovejs-build .

docker run --rm -v "$PWD:/work" \
  -v /path/to/megasource:/megasource -e MEGASOURCE=/megasource \
  lovejs-build ./build_lovejs.sh
```

### Linux / macOS

```
git clone --recursive https://github.com/dreagledr/megasource.git
git clone https://github.com/emscripten-core/emsdk.git ~/emsdk
~/emsdk/emsdk install 2.0.0
~/emsdk/emsdk activate 2.0.0

./build_lovejs.sh --emsdk ~/emsdk --megasource ./megasource
```

The artifacts are staged into `src/compat` and `src/release` (release also gets
`love.worker.js`). Commit them — the tooling relies on these prebuilt binaries.

Options:

```
-e, --emsdk DIR       emsdk checkout (2.0.0); defaults to $EMSDK
-m, --megasource DIR  megasource checkout; defaults to $MEGASOURCE
-l, --love DIR        build a love checkout instead of megasource's libs/love
                      submodule (passed as -DMEGA_LOVE); defaults to $LOVE
    --out DIR         where the binaries go [<repo>/src]
    --build DIR       build directory [<repo>/build]
    --targets LIST    compat,release [compat,release]
    --jobs N          parallel jobs [number of CPUs]
    --clean           delete the build directory first
```

## License
MIT, see [LICENSE](LICENSE). LÖVE itself is zlib-licensed; see the
[love](https://github.com/dreagledr/love) and
[megasource](https://github.com/dreagledr/megasource) forks.
