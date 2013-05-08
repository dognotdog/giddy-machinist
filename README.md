# Status

As of now, an STL or G-Code can be loaded and displayed. The STL is sliced into layer outlines, which can then be inspected and used to generate some offset curves. This works via generating a motorcycle graph, then straight skeleton of the input polygon. Various display options for debugging the process are available.

Any of the stages so far often crashes or produces incorrect output.

## Next Milestone

For some layer outline, generate properly offset perimeters and infill, while detecting thin segments and filling them properly.

# Dependencies

Requires stuff from http://github.com/dognotdog/mac-common/
