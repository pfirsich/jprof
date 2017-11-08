# jprof

Usually Lua programs are profiled by setting hooks using the built-in function `debug.sethook`, but sadly these hooks are not reliably called in luajit, which makes most profiling libraries for Lua not usable in the current version of [löve](https://love2d.org/).

jprof is a semi-makeshift solution for profiling löve applications with some extra work, but while also providing no significant slowdown while profiling.

# Overview
jprof requires you to annotate your code with "profiling zones", which form a hierarchical representation of the overall flow of your program and record time taken and memory consumption for each of these zones:
```lua
function foo()
    prof.push("do the thing")
    thething()
    prof.pop()
end

function bar()
    prof.push("foo it up in here")
    foo()
    prof.pop("foo it up in here")

    prof.push("something else")
    local baz = sum(thing, else)
    prof.pop("something else")
end
```

Then calling `prof.write("myfile.prof")` will save a file to your applications save directory using [fperrad/lua-MessagePack](https://github.com/fperrad/lua-MessagePack), which you can analyze in the viewer:

![Time mode](https://user-images.githubusercontent.com/2214632/32568512-c2a04ec8-c4be-11e7-8964-cda8d96f4e9e.png)

![Memory mode](https://user-images.githubusercontent.com/2214632/32566607-c39c648e-c4b8-11e7-88a5-a6f5d17d6b2c.png)

# Documentation
Before you annotate your code, you need to copy (!) `jprof.lua` and `MessagePack.lua` into your game's directory.

If you want to capture a profiling file, you need to set `PROF_CAPTURE` before you import jprof:
```lua
PROF_CAPTURE = true
prof = require "jprof"
```

If `PROF_CAPTURE` evaluates to `false` when jprof is imported, all profiling functions are replaced with `function() end` i.e. do nothing, so you can leave them in even for release builds.

Also all other zones have to be pushed inside the `"frame"` zone and whenever `prof.push` or `prof.pop` are called outside of a frame, the viewer will not know how to interpret that data (and error). The idiomatic use is therefore something like this:
```lua
function love.update(dt)
    prof.enabled(true)
    prof.push("frame")
    -- push and pop more here
    -- also update your game if you want
    prof.pop("frame")
    prof.enabled(false)
end
```
This makes sure that if functions that push profiling zones are used outside of `love.update`, the captures can still be interpreted by the viewer.


### `prof.push(name, annotation)`
The annotation is optional and appears as metadata in the viewer.

### `prof.pop(name)`
The name is optional and is only used to check if the current zone is actually the one specified as the argument. If not, somewhere before that pop-call another zone has been pushed, but not popped.

### `prof.write(filename)`
Writes the capture file

### `prof.enabled(enabled)`
Enables capturing profiling zones (`enabled = true`) or disables it (`enabled = false`)

# Viewer
You can seek frames with left-click. If you hold shift while pressing left-click the previously selected frame and the newly clicked frame will be averaged into a frame range, which is highly advised to find bottlenecks or get a general idea of memory development when you are not interested in a particular frame.
If a single frame is selected, you can additionally navigate using the left and right arrow key and skip 100 instead of 1 frame, if you also hold ctrl.
If a single frame is selected the position of the zones in the flame graph will correspond to their relative position in time inside the frame, for averaged frames both in memory and time mode the zones will just be centered above their parent. Their size will still hold meaning though and empty space surrounding these zones implies that there was memory consumed/freed or time spent without being enclosed by a profiling zone.

With the space key you can switch between memory and time mode, which display the flame while either taking memory consumption changes or time duration into account for positioning and scaling the zones respectively.

The purple graph displays the total duration of the frames over time and the green graph the total memory consumption over time.
