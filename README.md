# gtfs_to_igraph

## This repo presents a function convert a GTFS feed (or a list of GTFS feeds) into an `igraph` object for network analysis in `R`.

The workflow of the function is as follows:
 - Step 0: Read the GTFS data into memory
 - Steps 1 to 3: Identify and merge stops that are closer than a distance threshold (meters). This threshold is set by the user
 - Step 4: Identify transport modes, route and service level for each trip
 - Step 5: Indentify links between stops
 - Step 6: Build igraph
 - Step 7 (optional): the script saves the input files to use in [MuxViz](https://github.com/manlius/muxViz)
