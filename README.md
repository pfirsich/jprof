# jprof

Usually Lua programs are profiled by setting hooks using debug.sethook, but sadly these hooks are not reliably called in luajit, which makes most profiling libraries for Lua not usable in the current version of [löve](https://love2d.org/).

jprof is a semi-makeshift solution for profiling löve applications.

# Overview
jprof requires you to annotate your code with "profiling zones", which form a hierarchical representation of the overall flow of your program and record time taken and memory consumption changes for each of these zones:
```
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

Then calling `prof.write("myfile.prof")` will save a file to your applications save directory, which you can analyze in the viewer:

![Time mode](https://user-images.githubusercontent.com/2214632/32566609-c3b96d40-c4b8-11e7-9aa5-1c77acf04595.png)

![Memory mode](https://user-images.githubusercontent.com/2214632/32566607-c39c648e-c4b8-11e7-88a5-a6f5d17d6b2c.png)
