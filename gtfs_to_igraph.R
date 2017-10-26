

##############################################################################################
################### This script brings a function to convert a list        ###################
################### of GTFS.zip files into an igraph for network analysis  ###################
##############################################################################################
# github repo: https://github.com/rafapereirabr/gtfs_to_igraph




##################### Load packages -------------------------------------------------------

library(igraph)
library(data.table)
library(dplyr)
library(magrittr)
library(sp)
library(geosphere)




### Start Function
  
gtfs_to_igraph <- function( list_gtfs, dist_threshold, save_muxviz){


############ 0. read GTFS files   -----------------

# list_gtfs= list_of_gtfs_feeds
# dist_threshold = 30

  
  cat("reading GTFS data \n")

# function to read and rbind files from a list with different GTFS.zip
  tmpd <- tempdir()
  unzip_fread_gtfs <- function(zip, file) { unzip(zip, file, exdir=tmpd) %>% fread(colClasses = "character") }
  unzip_fread_routes <- function(zip, file) { unzip(zip, file, exdir=tmpd) %>% fread(colClasses = "character", select= c('route_id', 'route_short_name', 'route_type', 'route_long_name')) }
  unzip_fread_trips <- function(zip, file) { unzip(zip, file, exdir=tmpd) %>% fread(colClasses = "character", select= c('route_id', 'service_id', 'trip_id', 'direction_id')) }
  unzip_fread_stops <- function(zip, file) { unzip(zip, file, exdir=tmpd) %>% fread(colClasses = "character", select= c('stop_id', 'stop_name', 'stop_lat', 'stop_lon', 'parent_station', 'location_type')) }
  unzip_fread_stoptimes <- function(zip, file) { unzip(zip, file, exdir=tmpd) %>% fread(colClasses = "character", select= c('trip_id', 'arrival_time', 'departure_time', 'stop_id', 'stop_sequence')) }

# Read
  stops <- lapply( list_gtfs , unzip_fread_stops, file="stops.txt")  %>% rbindlist()
  stop_times <- lapply( list_gtfs , unzip_fread_stoptimes, file="stop_times.txt")  %>% rbindlist()
  routes <- lapply( list_gtfs , unzip_fread_routes, file="routes.txt")  %>% rbindlist()
  trips <- lapply( list_gtfs , unzip_fread_trips, file="trips.txt")  %>% rbindlist()
  calendar <- lapply( list_gtfs , unzip_fread_gtfs, file="calendar.txt")  %>% rbindlist()

# make sure lat long are numeric, and text is encoded
  stops[, stop_lon := as.numeric(stop_lon) ][, stop_lat := as.numeric(stop_lat) ]
  Encoding(stops$stop_name)  <- "UTF-8" 



############  1. Identify stops that closee than distance Threshold in meters  ------------------
  cat("calculating distances between stops \n")
  
  ### Convert stops into SpatialPointsDataFrame
  
      # lat long projection
        myprojection_latlong <- CRS("+proj=longlat +datum=WGS84 +ellps=WGS84 +towgs84=0,0,0")
      
      # convert stops into spatial points
        coordinates(stops) <- c("stop_lon", "stop_lat")
        proj4string(stops) <- myprojection_latlong
        stops <- spTransform(stops, myprojection_latlong)
  
  # use the distm function to generate a geodesic distance matrix in meters
    mdist <- distm(stops, stops, fun=distHaversine)
    

  # cluster all points using a hierarchical clustering approach
    hc <- hclust(as.dist(mdist), method="complete")
  
  # define clusters based on a tree "height" cutoff "d" and add them to the SpDataFrame
    stops@data$clust <- cutree(hc, h=dist_threshold)
    gc(reset = T)


# convert stops back into  data frame
  df <- as.data.frame(stops) %>% setDT()
  df <- df[order(clust)]
  df <- unique(df) # remove duplicate of identical stops
  head(df)

# identify how many stops per cluster
  df[, quant := .N, by = clust]
  table(df$quant)


  plot(df$stop_lon, df$stop_lat, col=df$clust)

  
  
  
  
############ 2. Identify and update Parent Stations  ------------------

cat("Identifying and updating Parent Stations \n")
  
  
# How many stops have a Parent Station 
  nrow(df[ parent_station !=""])

  
# How many stops without Parent Station 
  nrow(df[ parent_station ==""])


# Stops which are Parent Stations (location_type==1) will be Parent Stations of themselves
  df[ location_type==1, parent_station := stop_id ]
  
  # in case the field location_type is missinformed 
  df[ parent_station=="" & stop_id %in% df$parent_station, parent_station := stop_id ]
  df[ quant > 1 , parent_station:= ifelse( parent_station !="" , parent_station,
                                           ifelse( parent_station=="" & stop_id %in% df$parent_station, stop_id, "")), by=clust]

#total number of stops without Parent Station
nrow(df[ parent_station ==""])




# Update Parent Stations for each cluster
  
  # a) Stops which alread have parent stations stay the same

  # b) stations with no parent, will receive the parent of the cluster
    df[ quant > 1 , parent_station:= ifelse( parent_station !="" , parent_station,
                                     ifelse( parent_station=="", max(parent_station), "")), by=clust]

    nrow(df[ parent_station ==""])


  # d) For those clusters with no parent stations, get the 1st stop to be a Parent
    df[ quant > 1 , parent_station:= ifelse( parent_station !="" , parent_station,
                                             ifelse( parent_station== "", stop_id[1L], "")), by=clust]
  
    nrow(df[ parent_station ==""])

  # all clusters > 1 have a parent station                                     
    df[quant > 1 & parent_station==""][order(clust)] # should be empty


# Remaining stops without Parent Station
  nrow(df[ parent_station ==""]) 


# make sure parent stations are consistent within each cluster with more than one stop
  df[ quant > 1 , parent_station := max(parent_station), by=clust]
  unique(df$parent_station) %>% length()


# for the lonly stops, make sure they are the Parent station of themselves
  df[ quant ==1 & parent_station=="" , parent_station := stop_id , by=stop_id]
  nrow(df[ parent_station ==""]) == 0
  

  

############ 3. Update Lat long of stops based on parent_station -----------------------


# Update in stops data: get lat long to be the same as 1st Parent Station
  df[, stop_lon := stop_lon[1],  by=parent_station]
  df[, stop_lat := stop_lat[1],  by=parent_station]


  
# Update in stop_times data: get lat long to be the same as 1st Parent Station
  
    
  # Add parent_station info to stop_times
    # merge stops and stop_times based on correspondence btwn stop_times$stop_id and df$stop_id
    stop_times[df, on= 'stop_id', c('clust', 'parent_station') := list(i.clust, i.parent_station) ]
  
  
  
  # CRUX: Replace stop_id with parent_station
    stop_times[ !is.na(parent_station) , stop_id := parent_station ]
    df[ , stop_id := parent_station ]
  
  # remove repeated stops
    df <- unique(df)



    
############ 4. identify transport modes, route and service level for each trip  -----------------------
    
  routes <- routes[,.(route_id, route_type)]                # keep only necessary cols
  trips <- trips[,.(route_id, trip_id, service_id)]         # keep only necessary cols
  trips[routes, on=.(route_id), route_type := i.route_type] # add route_type to trips

# add these columns to stop_times: route_id, route_type, service_id
  stop_times[trips, on=.(trip_id), c('route_id', 'route_type', 'service_id') := list(i.route_id, i.route_type, i.service_id) ]
  gc(reset = T)


# # Only keep trips during weekdays 
#   # remove columns with weekends
#   calendar <- calendar[, -c('saturday', 'sunday')]
#   
#   # keep only rows that are not zero (i.e. that have service during weekday)
#   calendar <- calendar[rowMeans(calendar >0)==T,]
#   
#   # Only keep those trips which run on weekdays
#   stop_times2 <- subset(stop_times, service_id %in% calendar$service_id)

  

# Get edited info for stop_times and stops
  stops_edited <- df[, .(stop_id, stop_name, parent_station, location_type, stop_lon, stop_lat)]
  stop_times_edited <- stop_times[, .(route_type, route_id, trip_id, stop_id, stop_sequence, arrival_time, departure_time)]
  
  # make sure stop_sequence is numeric
  stop_times_edited[, stop_sequence := as.numeric(stop_sequence) ]
  
  gc(reset = T)

  



############ 5. Indentify links between stops   -----------------
  cat("Identifying links between stops \n")
  

  # create three new columns by shifting the stop_id, arrival_time and departure_time of the following row up 
    # you can do the same operation on multiple columns at the same time
    stop_times_edited[, `:=`(stop_id_to = shift(stop_id, type = "lead"), 
                          arrival_time_stop_to = shift(arrival_time, type = "lead"),
                          departure_time_stop_to = shift(departure_time, type = "lead")),
                   by = .(trip_id, route_id)]
      
  # you will have NAs at this point because the last stop doesn't go anywhere. Let's remove them
  stop_times_edited <- na.omit(stop_times_edited) 
  
  # get weight: frequency per route
    relations <- stop_times_edited[, .(weight = .N), by= .(stop_id, stop_id_to, route_id, route_type)]
    relations <- unique(relations)
    
    # reorder columns
    setcolorder(relations, c('stop_id', 'stop_id_to', 'weight', 'route_id', 'route_type'))
    
    
  # now we have 'from' and 'to' columns from which we can create an igraph
    head(relations)
  
    # plot densit distribution of trip frequency
    density(relations$weight) %>% plot() 
    
    
  # subset stop columns
    temp_stops <- stops_edited[, .(stop_id, stop_lon, stop_lat)]     #
    temp_stops <- unique(temp_stops)
  

# remove stops with no connections, and remove connections with ghost stops
  e <- unique(c(relations$stop_id, relations$stop_id_to))
  v <- unique(temp_stops$stop_id)      
  
  d <- setdiff(v,e)  # stops in vertex data frame that are not present in edges data 
  dd <- setdiff(e,v) # stops in edges data frame that are not present in vertex data
  
  temp_stops <- temp_stops[ !(stop_id %in% d) ]   # stops with no connections
  relations <- relations[ !(stop_id %in% dd) ]    # trips with ghost stops
  relations <- relations[ !(stop_id_to %in% dd) ] # trips with ghost stops
  
  
  
#######  Overview of the network being built 
  
    cat("Number of nodes:", unique(relations$stop_id) %>% length(), " \n")
    cat("Number of Edges:", nrow(relations), " \n")
    cat("Number of routes:",  unique(relations$route_id) %>% length(), " \n")
    


    
############ 6. Build igraph ---------------------
    cat("building igraph \n")
  
  g <- graph_from_data_frame(relations, directed=TRUE, vertices=temp_stops)
  
  
  
  
############ 7. Save MuxViz input ----------------------------------
  
  cat("saving muxviz input \n")
  
if (save_muxviz==T){ 
  
  # create directory where input files to muxviz will be saved
  dir.create(file.path(".", "muxviz_input"), showWarnings = FALSE)
  
  # stops
    names(temp_stops) <- c('nodeID', 'nodeLong', 'nodeLat')
    temp_stops[, nodeLabel := nodeID]
    setcolorder(temp_stops, c('nodeID', 'nodeLabel', 'nodeLong', 'nodeLat'))
    
    fwrite( temp_stops, "./muxviz_input/stops_layout.txt")
  
  # Edges
    #recode route type by tranport mode
    relations[, route_type := ifelse(route_type==0, "LightRail", ifelse(route_type==1, "Subway", ifelse(route_type==2, "Rail",
                              ifelse(route_type==3, "Bus", ifelse(route_type==4, "Ferry",
                              ifelse(route_type==5, "Tramway", ifelse(route_type==6, "CableCar",
                              ifelse(route_type==7, "Funicular", "ERROR"))))))))]
    
    # save links data for each tranport mode in a separate .txt file
      cols_to_save <- c('stop_id', 'stop_id_to', 'weight')
      relations[, fwrite(.SD, paste0("./muxviz_input/edge_list_", route_type ,".txt"),
                          col.names = F, sep = " "), by = route_type, .SDcols= cols_to_save]
    
  # create Input file
    edge_files <- list.files("./muxviz_input", pattern="edge_list", full.names=F)
    layout_file <- list.files("./muxviz_input", pattern="layout", full.names=F)
    
    input_file <- data.frame(a= edge_files, b = NA, c=layout_file)
    input_file$a <- input_file$a
    input_file$b <- gsub('^.*_\\s*|\\s*.t.*$', '', input_file$a)
    input_file$c <- input_file$c
    fwrite(x=input_file, file="./muxviz_input/input_Muxviz.txt" ,col.names = F, sep = ";" )
  }   
  
  # return graph
  return(g)
  
}


