# gtfs_to_igraph

## This repo presents a function convert a GTFS feed (or a list of GTFS feeds) into an `igraph` object for network analysis in `R`.


### Workflow
The workflow of the function is as follows:
 - Step 0: Read the GTFS data into memory
 - Steps 1 to 3: Identify and merge stops that are closer than a distance threshold (meters). This threshold is set by the user
 - Step 4: Identify transport modes, route and service level for each trip
 - Step 5: Indentify links between stops
 - Step 6: Build igraph
 - Step 7 (optional): the script creates a subdirectory and saves the input files to use in [MuxViz](https://github.com/manlius/muxViz)



### Input
This function needs three inputs: 
 - list with one or more files `gtfs.zip`
 - a distance threshold set in meters
 - a logic value indicating whether you want to save input files to use latter in MuxViz

obs. This function was tested using the GTFS of Las Vegas, USA, downloaded on Oct. 2017. This file is made available in the GitHub repo but it can also be downloaded by running this line in `R`: 

`download.file(url="http://rtcws.rtcsnv.com/g/google_transit.zip", destfile = "google_transit.zip")`


### How to use the function
```
# set working Directory
  setwd("R:/Dropbox/github/gtfs_to_igraph")

# get a list of GTFS.zip files
  my_gtfs_feeds <- list.files(path = ".", pattern =".zip", full.names = T)

# load function
  source("gtfs_to_igraph.R")

# run function
  g <- gtfs_to_igraph(list_gtfs = my_gtfs_feeds,  dist_threshold =30 , save_muxviz =T)
```




