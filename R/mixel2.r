#' Composite images 
#'
#' Composite images
#' @param msswrs1dir character. list of mss wrs1 directory paths
#' @param msswrs2dir character. list of mss wrs2 directory paths
#' @param tmwrs2dir character. list of tm wrs2 directory path
#' @param index character. spectral index to make composites for. options: "tca", "tcb", "tcg", "tcw"
#' @param outdir character. path to output directory
#' @param runname character. unique name for the composite set
#' @param useareafile character. path to usearea file
#' @param doyears ??? what years to composite
#' @param order character. how to order the images options "sensor_and_doy" and "doy"
#' @param overlap character. how to deal with overlapping images. options: "mean"
#' @import raster
#' @import gdalUtils
#' @import ggplot2
#' @import plyr
#' @export


mixel2 = function(msswrs1dir,msswrs2dir,tmwrs2dir,index,outdir,runname,useareafile,doyears="all",order="none",overlap="mean"){
  
  mixel_find = function(files, refimg){
    
    #get the extents of the files
    info = matrix(ncol = 4, nrow=length(files))
    print("Getting image extents")
    for(i in 1:length(files)){ 
      print(i)
      img = raster(files[i])
      ext = extent(img)
      info[i,1] = ext@xmin
      info[i,2] = ext@xmax
      info[i,3] = ext@ymin
      info[i,4] = ext@ymax
    }
    
    text = extent(raster(refimg))  
    these = which(info[,3] < text@ymax & info[,4] > text@ymin & info[,2] > text@xmin & info[,1] < text@xmax) 
    goods = files[these]
    return(goods)
  }
  
  mixel_mask = function(imgfile, refimg, index){ #search,
    if(index == "tca" | index == "tcb"){band=1}
    if(index == "tcg"){band=2}
    if(index == "tcw"){band=3}
    
    sensor = substr(basename(imgfile), 1,2)
    if(sensor == "LM"){maskbit = "_cloudmask_30m.tif"} else {maskbit = "_cloudmask.tif"}
    
    maskfile = file.path(dirname(imgfile), paste(substr(basename(imgfile),1,16),maskbit,sep=""))
    #maskfile = sub(search, searchmask,imgfile) #"cloudmask.tif"
    print(basename(maskfile))
    print(file.exists(maskfile))
    img = raster(imgfile, band=band)
    mask = raster(maskfile)
    
    imgex = alignExtent(img, refimg, snap="near")
    maskex = alignExtent(mask, refimg, snap="near")
    extent(img) = imgex
    extent(mask) = maskex
    
    overlap = intersect(img, mask)
    mask = crop(mask, overlap)
    img = crop(img, overlap)
    
    bads = which(values(mask) == 0)
    img[bads] = NA
    #outfile = file.path("E:/llr_test/mosaic_prep",basename(imgfile))
    #writeRaster(img,outfile,datatype="INT2S")
    return(img)
  }
  
  mixel_composite = function(outdir, files, runname, index, doyears, order, useareafile, overlap, offset, adj=NULL, offsetrun){
    #create an output directory
    
    #extract some info from the filenames
    filebase = basename(files)
    years = substr(filebase, 10, 13)
    days = substr(filebase, 14,16)
    sensor = substr(filebase, 1,3)
    yearsort = sort(unique(years))
    medday = median(as.numeric(days))
    
    #load in the reference image (usearea file)
    refimg = raster(useareafile)
    newimgnas = values(refimg) == 0
    #nas = values(refimg) == 1
    
    if(doyears == "all"){uni=yearsort} else {
      theseyears = match(doyears,yearsort)
      uni = yearsort[theseyears]
    }
    
    #for all the unique year make a composite
    for(i in 1:length(uni)){
      ptm <- proc.time()
      if(is.na(uni[i] == T)){next}
      print(paste("working on year:", uni[i]))
      
      refimg = raster(useareafile)
      #refimg[nas] = NA
      
      these = which(years == uni[i])
      theseimgs = files[these]
      thesedays = days[these]
      thesesensors = sensor[these]
      meddif = abs(as.numeric(thesedays)-medday)
      
      if(order == "none"){imgorder = theseimgs}
      
      #day of year order - no sensor consideration
      if(order == "doy"){
        difsort = sort(meddif, index.return = T)
        imgorder = theseimgs[difsort$ix]
      }
      
      #use this section if TM is to always come first in the img merge order
      if(order == "sensor_and_doy"){
        #separate the sensors
        tmid = which(thesesensors == "LT5" | thesesensors == "LT4")
        etmid = which(thesesensors == "LE7")
        mssid = which(thesesensors != "LE7" & thesesensors != "LT5" & thesesensors != "LT4")
        
        #extract images for each sensor
        tmimg = theseimgs[tmid]
        etmimg = theseimgs[etmid]
        mssimg = theseimgs[mssid]
        
        #sort each sensor by image date
        tmmeddiff = sort(meddif[tmid], index.return = T)
        etmmeddiff = sort(meddif[etmid], index.return = T)
        mssmeddiff = sort(meddif[mssid], index.return = T)
        
        #reorder the images
        tmorder = tmimg[tmmeddiff$ix]
        etmorder = etmimg[etmmeddiff$ix]
        mssorder = mssimg[mssmeddiff$ix]
        
        #out them all together
        imgorder = c(tmorder, etmorder, mssorder)
      }
      len = length(these)
      print("merging files:")
      for(m in 1:len){
        print(basename(imgorder[m]))
        if(m == 1){mergeit = "r1"} else {mergeit = paste(mergeit,",r",m, sep="")}
        #run the image prep function on-the-fly
        dothis = paste("r",m,"=mixel_mask(imgorder[",m,"], refimg, index)", sep="") #search,
        eval(parse(text=dothis))
        if(m == len){
          if(overlap == "order"){mergeit = paste("newimg = merge(",mergeit,")", sep="")} #,refimg
          if(overlap == "mean"){mergeit = paste("newimg = mosaic(",mergeit,",fun=mean,na.rm=T,tolerance=0.5)", sep="")}  #refimg
          if(overlap == "median"){mergeit = paste("newimg = mosaic(",mergeit,",fun=median,na.rm=T)", sep="")}
        }
      }
      
      #run the merge function
      if(len == 1){newimg = r1} else {eval(parse(text=mergeit))} #only run merge it if there are multiple files to merge
      
      #name the new file
      newbase = paste(uni[i],"_",runname,"_",index,"_composite.bsq", sep="")  #.tif #tsa,"_",
      outimgfile = file.path(outdir,newbase)  
      outtxtfile = sub("composite.bsq", "composite_img_list.csv", outimgfile)
      imgorder = data.frame(imgorder)
      colnames(imgorder) = "File"
      write.csv(imgorder, file=outtxtfile)
      
      #crop it and set na values to 0
      #       newimg = round(crop(newimg, refimg))
      #       newimg = extend(newimg, refimg, value=NA)
      #       if(is.null(adj) == F){newimg = sum(newimg, raster(adj), na.rm=T)}
      #       if(offsetrun == T){newimg[(values(refimg) == 0)] = NA} else{
      #         newimg[(values(refimg) == 0)] = 0
      #         newimg[is.na(newimg)] = 0
      #       }
      
      newimg = round(crop(newimg, refimg))
      newimg = extend(newimg, refimg, value=NA)
      #newimg[(values(refimg) == 0)] = NA      
      newimg[newimgnas] = NA
      if(is.null(adj) == F){newimg = newimg + raster(adj)}
      if(offsetrun == F){
        #newimg[(values(refimg) == 0)] = 0
        newimg[newimgnas] = 0
        newimg[is.na(newimg)] = 0
      }
      #write out the new image
      projection(newimg) = set_projection(files[1])
      
      writeRaster(newimg, outimgfile, format="ENVI", datatype = "INT2S",overwrite=T)
      envifilename = sub("bsq","envi",outimgfile)
      envixmlfile = paste(envifilename,".aux.xml",sep="")
      bsqxmlfile = sub("envi","bsq",envixmlfile)
      file.rename(envifilename,outimgfile)
      file.rename(envixmlfile,bsqxmlfile)
      
#       newimg = as(newimg, "SpatialGridDataFrame") #convert the raster to SGHF so it can be written using GDAL (faster than writing it with the raster package)
#       writeGDAL(newimg, outimgfile, drivername = "ENVI", type = "Int16", mvFlag = -32768) #, options="INTERLEAVE=BAND"
            
      tempdir = dirname(rasterTmpFile())
      print(paste("this is the tempdir:",tempdir))      
      tempfiles = list.files(tempdir,full.names=T)
      print(paste("there are:",length(tempfiles),"files found"))
      unlink(tempfiles)
      tempfiles = list.files(tempdir,full.names=T)
      print(paste("after attempting to delete them, there are:",length(tempfiles),"files"))
      print(proc.time()-ptm) 
    }
  }
  
  
  if(index == "tca"){msssearch="tca_30m.tif$"; tmsearch="tca.tif$"}
  if(index == "tcb"){msssearch="tc_30m.tif$"; tmsearch="tc.tif$"}
  if(index == "tcg"){msssearch="tc_30m.tif$"; tmsearch="tc.tif$"}
  if(index == "tcw"){msssearch="tc_30m.tif$"; tmsearch="tc.tif$"}
  
  #find files
  msswrs1imgdir = file.path(msswrs1dir,"images")
  msswrs2imgdir = file.path(msswrs2dir,"images")
  tmwrs2imgdir = file.path(tmwrs2dir,"images")
  
  for(i in 1:length(msswrs1dir)){
    if(i == 1){msswrs1files = list.files(msswrs1imgdir[i], msssearch, recursive=T, full.names=T)} else {
      msswrs1files = c(msswrs1files,list.files(msswrs1imgdir[i], msssearch, recursive=T, full.names=T))
    }
  }
  for(i in 1:length(msswrs2dir)){
    if(i == 1){msswrs2files = list.files(msswrs2imgdir[i], msssearch, recursive=T, full.names=T)} else {
      msswrs2files = c(msswrs2files,list.files(msswrs2imgdir[i], msssearch, recursive=T, full.names=T))
    }
  }  
  
  for(i in 1:length(tmwrs2dir)){
    if(i == 1){tmwrs2files = list.files(tmwrs2imgdir[i], tmsearch, recursive=T, full.names=T)} else {
      tmwrs2files = c(tmwrs2files, list.files(tmwrs2imgdir[i], tmsearch, recursive=T, full.names=T))
    }
  }
  
  files = c(msswrs1files,msswrs2files,tmwrs2files)
  files = mixel_find(files, useareafile)
  
  #organize files
  sensor = substr(basename(files), 1,2)
  mssfiles = files[which(sensor == "LM")]
  tmfiles = files[which(sensor != "LM")]
  mssyears = substr(basename(mssfiles), 10, 13)
  tmyears = substr(basename(tmfiles), 10, 13)
  thesetm = which(tmyears %in% mssyears)
  overlaptmfiles = tmfiles[thesetm]
  thesemss = which(mssyears %in% tmyears)
  overlapmssfiles = mssfiles[thesemss]
  offsetdir = file.path(outdir,"offset")
  dir.create(outdir, recursive=T, showWarnings=F)
  
  if(length(overlapmssfiles) == 0 | length(overlaptmfiles) == 0){
    mixel_composite(outdir, files, runname=runname,index=index, doyears=doyears, order=order, useareafile=useareafile, overlap=overlap, offsetrun=F)
  } else {
    
    #start offset finding procedure
    offsetdir = file.path(outdir,"offset")
    dir.create(offsetdir, recursive=T, showWarnings=F)
    #composite mss calibration images
    mixel_composite(offsetdir, overlapmssfiles, runname="lm",index=index, doyears=doyears, order=order, useareafile=useareafile, overlap=overlap, offsetrun=T)
    #composite tm calibration images
    mixel_composite(offsetdir, overlaptmfiles, runname="lt",index=index, doyears=doyears, order=order, useareafile=useareafile, overlap=overlap, offsetrun=T)
    
    #find the composite images, check and sort them
    offsetfiles = list.files(offsetdir, ".bsq$", full.names=T)
    mssoffsetfiles = offsetfiles[which(substr(basename(offsetfiles), 6,7) == "lm")]
    tmoffsetfiles = offsetfiles[which(substr(basename(offsetfiles), 6,7) == "lt")]
    if(length(mssoffsetfiles) == length(tmoffsetfiles)){
      mssyear = substr(basename(mssoffsetfiles),1,4)
      tmyear = substr(basename(tmoffsetfiles),1,4)
      mssofff = mssoffsetfiles[order(mssyear)]
      tmofff = tmoffsetfiles[order(tmyear)]
    } else {stop("there is not a matching number of MSS and TM years in the offset folder, can't continue")}
    
    #find the mean pixel-wise difference between mss and tm images
    for(i in 1:length(mssofff)){
      print(i)
      if(i == 1){dif = raster(tmofff[i]) - raster(mssofff[i])} else{
        dif = sum(dif,(raster(tmofff[i]) - raster(mssofff[i])), na.rm=T)
      }
    }
    
    meandiforig = round(dif/length(mssofff))
    projection(meandiforig) = set_projection(files[1])
    
    meandiffile = file.path(offsetdir,"mean_dif.bsq")
    writeRaster(meandiforig, meandiffile, format="ENVI", datatype = "INT2S",overwrite=T)
    envifilename = sub("bsq","envi",meandiffile)
    envixmlfile = paste(envifilename,".aux.xml",sep="")
    bsqxmlfile = sub("envi","bsq",envixmlfile)
    file.rename(envifilename,meandiffile)
    file.rename(envixmlfile,bsqxmlfile)
    
    
#     using writeRaster in case the files are huge - it can chunk them up
#     meandif = as(meandiforig, "SpatialGridDataFrame") #convert the raster to SGHF so it can be written using GDAL (faster than writing it with the raster package)
#     meandiffile = file.path(offsetdir,"mean_dif.bsq")
#     writeGDAL(meandif, meandiffile, drivername = "ENVI", type = "Int16", mvFlag = -32768) #, options="INTERLEAVE=BAND"
    
    meandif=0 #memory

    #adjust the mss composites to reflect the offset
    for(i in 1:length(mssofff)){
      print(paste("adjusting mss file:", mssofff[i]))
      r = raster(mssofff[i]) + meandiforig
      projection(r) = set_projection(files[1])
      
      outimgfile = sub("composite.bsq","composite_adj.bsq",mssofff[i])
      
      writeRaster(r, outimgfile, format="ENVI", datatype = "INT2S",overwrite=T)
      envifilename = sub("bsq","envi",outimgfile)
      envixmlfile = paste(envifilename,".aux.xml",sep="")
      bsqxmlfile = sub("envi","bsq",envixmlfile)
      file.rename(envifilename,outimgfile)
      file.rename(envixmlfile,bsqxmlfile)
#       using writeRaster in case the files are huge - it can chunk them up
#       r = as(r, "SpatialGridDataFrame") #convert the raster to SGHF so it can be written using GDAL (faster than writing it with the raster package)
#       outimgfile = sub("composite.bsq","composite_adj.bsq",mssofff[i])
#       writeGDAL(r, outimgfile, drivername = "ENVI", type = "Int16", mvFlag = -32768) #, options="INTERLEAVE=BAND"
    }
    #r=0 #memory
    
    #sample the composites to calculate RMSE
#     print("determing offset between unadjusted and adjusted mss data")
#     n_random = 5000
#     n_years = length(mssofff)
#     coords = sampleRandom(meandiforig, size=n_random, na.rm=TRUE, xy=T)
#     coords = data.frame(point=seq(1:nrow(coords)),x=coords[,1],y=coords[,2])
#     if(index == "tca"){difvalue = extract(meandiforig, coords[,2:3])/100} else{
#       difvalue = extract(meandiforig, coords[,2:3])
#     }
#     
#     for(f in 1:length(mssofff)){  #
#       if(index == "tca"){
#         mssvalue = extract(raster(mssofff[f]),coords[,2:3])/100
#         tmvalue = extract(raster(tmofff[f]),coords[,2:3])/100
#       } else{
#         mssvalue = extract(raster(mssofff[f]),coords[,2:3])
#         tmvalue = extract(raster(tmofff[f]),coords[,2:3])
#       }
#       origdif = tmvalue-mssvalue
#       adjdif = tmvalue-(mssvalue+difvalue)
#       year = substr(basename(mssofff[f]),1,4)
#       if(f == 1){fulldf = data.frame(coords,year,tmvalue,mssvalue,difvalue,origdif,adjdif)} else {
#         df = data.frame(coords,year,tmvalue,mssvalue,difvalue,origdif,adjdif)
#         fulldf = rbind(fulldf, df)
#       }
#     }
#     print("preparing mss offset table")
#     fulldf = fulldf[complete.cases(fulldf),]
#     fulldf$origdifsqr = fulldf$origdif^2
#     fulldf$adjdifsqr = fulldf$adjdif^2
#     fulldf$origabsdif = abs(fulldf$origdif)
#     fulldf$adjabsdif = abs(fulldf$adjdif)
#     outsampfile = file.path(offsetdir,"offset_sample.csv")
#     print("writing mss offset table")
#     write.csv(fulldf, outsampfile, row.names=F)
#     
#     print("calculating summaries of mss offset table")
#     origrmse = aggregate(fulldf$origdifsqr, by=list(fulldf$point), FUN=function(x){sqrt(sum(x, na.rm=T)/n_years)})
#     adjrmse = aggregate(fulldf$adjdifsqr, by=list(fulldf$point), FUN=function(x){sqrt(sum(x, na.rm=T)/n_years)})
#     origmae = aggregate(fulldf$origabsdif, by=list(fulldf$point), FUN=mean, na.rm=T)
#     adjmae = aggregate(fulldf$adjabsdif, by=list(fulldf$point), FUN=mean, na.rm=T)
#     
#     rmsesummary = data.frame(point=origrmse$Group.1,origrmse=origrmse$x,
#                              adjrmse=adjrmse$x,origmae=origmae$x,adjmae=adjmae$x)
# 
# #     remove dependency on plyr::ddply    
# #     rmsesummary = ddply(fulldf,.(point), here(summarize), 
# #                         origrmse = sqrt(sum(origdifsqr, na.rm=T)/n_years),
# #                         adjrmse = sqrt(sum(adjdifsqr, na.rm=T)/n_years),
# #                         origmae = mean(origabsdif, na.rm=T),
# #                         adjmae = mean(adjabsdif, na.rm=T))
#     
#     origrmsemean = mean(rmsesummary$origrmse, na.rm=T)
#     adjrmsemean = mean(rmsesummary$adjrmse, na.rm=T)
#     origmaemean = mean(rmsesummary$origmae, na.rm=T)
#     adjmaemean = mean(rmsesummary$adjmae, na.rm=T)
#     
#     #rmse
#     print("plotting mss offset table summaries")
#     d_origdif = density(fulldf$origdif)
#     d_adjdif = density(fulldf$adjdif)
#     d_max = max(d_origdif$y,d_adjdif$y)+0.01
#     pngout = file.path(offsetdir,"offset_histogram.png")
#     png(pngout, width = 800, height=700)
#     plot(d_origdif,
#          main="Mean offset between coincident MSS and TM annual composites for a sample of pixel time series",
#          xlab=index, col="blue",
#          ylim=c(0,d_max))
#     lines(d_adjdif, col="red")
#     abline(v=mean(fulldf$origdif,na.rm=T),lty=2, col="blue")
#     abline(v=mean(fulldf$adjdif,na.rm=T), lty=2, col="red")
#     legend(x=min(d_origdif$x),y=max(d_max),
#            c("no adjustment", "mean adjustment"),
#            lty=c(1,1),
#            col=c("blue", "red"))
#     dev.off()
#     
#     
#     d_origrmse = density(rmsesummary$origrmse)
#     d_adjrmse = density(rmsesummary$adjrmse)
#     d_max = max(d_origrmse$y,d_adjrmse$y)+0.05
#     pngout = file.path(offsetdir,"offset_rmse.png")
#     png(pngout, width = 800, height=700)
#     plot(d_origrmse,
#          main="RMSE for coincident MSS and TM annual composites for a sample of pixel time series",
#          xlab=index, col="blue",
#          ylim=c(0,d_max))
#     lines(d_adjrmse, col="red")
#     abline(v=origrmsemean,lty=2, col="blue")
#     abline(v=adjrmsemean, lty=2, col="red")
#     lxoff = ((max(d_origrmse$x) - adjrmsemean)*0.25) + adjrmsemean
#     legend(x=lxoff,y=max(d_max),
#            c("no adjustment", "mean adjustment"),
#            lty=c(1,1),
#            col=c("blue", "red"))
#     dev.off()
#     
#     
#     d_origmae = density(rmsesummary$origmae)
#     d_adjmae = density(rmsesummary$adjmae)
#     d_max = max(d_origmae$y,d_adjmae$y)+0.05
#     pngout = file.path(offsetdir,"offset_mae.png")
#     png(pngout, width = 800, height=700)
#     plot(d_origmae,
#          main="MAE for coincident MSS and TM annual composites for a sample of pixel time series",
#          xlab=index, col="blue",
#          ylim=c(0,d_max))
#     lines(d_adjmae, col="red")
#     abline(v=origmaemean,lty=2, col="blue")
#     abline(v=adjmaemean, lty=2, col="red")
#     lxoff = ((max(d_origmae$x) - adjmaemean)*0.25) + adjmaemean
#     legend(x=lxoff,y=max(d_max),
#            c("no adjustment", "mean adjustment"),
#            lty=c(1,1),
#            col=c("blue", "red"))
#     dev.off()
#     
# #     origrmsemean = mean(rmsesummary$origrmse, na.rm=T)
# #     adjrmsemean = mean(rmsesummary$adjrmse, na.rm=T)
# #     origrmsestdev = sd(rmsesummary$origrmse, na.rm=T)
# #     adjrmsestdev = sd(rmsesummary$adjrmse, na.rm=T)
# #     
# #     #rmse
# #     g = ggplot()+
# #       geom_density(data = fulldf, aes(x=origdif, fill="no adjustment"), alpha = 0.2)+
# #       geom_density(data = fulldf, aes(x=adjdif, fill="mean adjustment"), alpha = 0.2) +
# #       theme_bw()+
# #       xlab(index)+
# #       guides(fill = guide_legend(title = NULL))+
# #       ggtitle("Mean offset between coincident MSS and TM annual composites for a sample of pixel time series")
# #     
# #     pngout = file.path(offsetdir,"offset_histogram.png")
# #     png(pngout,width=800, height=700)
# #     print(g)
# #     dev.off()
# #     
# #     g = ggplot()+
# #       geom_density(data = rmsesummary, aes(x=origrmse, fill="no adjustment"), alpha = 0.2)+
# #       geom_density(data = rmsesummary, aes(x=adjrmse, fill="mean adjustment"), alpha = 0.2) +
# #       theme_bw()+
# #       xlab(paste(index,"rmse"))+
# #       guides(fill = guide_legend(title = NULL))+
# #       ggtitle("RMSE for coincident MSS and TM annual composites for a sample of pixel time series")
# #     
# #     pngout = file.path(offsetdir,"offset_rmse.png")
# #     png(pngout,width=800, height=700)
# #     print(g)
# #     dev.off()
# #     
# #     g = ggplot()+
# #       geom_density(data = rmsesummary, aes(x=origmae, fill="no adjustment"), alpha = 0.2)+
# #       geom_density(data = rmsesummary, aes(x=adjmae, fill="mean adjustment"), alpha = 0.2) +
# #       theme_bw()+
# #       xlab(paste(index,"mae"))+
# #       guides(fill = guide_legend(title = NULL))+
# #       ggtitle("MAE for coincident MSS and TM annual composites for a sample of pixel time series")
# #     
# #     pngout = file.path(offsetdir,"offset_mae.png")
# #     png(pngout,width=800, height=700)
# #     print(g)
# #     dev.off()
# #     
# #     g=fulldf=rmsesummary=0 #memory
#     
#     fulldf=rmsesummary=0 #memory

    #make final mss composites
    print("compositing mss data using adjustment")
    mssdir = file.path(outdir,"mss")
    dir.create(mssdir, recursive=T, showWarnings=F)
    mixel_composite(mssdir, mssfiles, runname=runname,index=index, doyears=doyears, order=order, useareafile=useareafile, overlap=overlap, adj=meandiffile, offsetrun=F)
    
    #make final tm composites
    print("compositing tm/etm+ data")
    tmdir = file.path(outdir,"tm")
    dir.create(tmdir, recursive=T, showWarnings=F)
    mixel_composite(tmdir, tmfiles, runname=runname,index=index, doyears=doyears, order=order, useareafile=useareafile, overlap=overlap, adj=NULL, offsetrun=F)
    
    #deal with the overlapping mss/tm composites
    print("dealing with overalapping mss and tm data")
    msscompfiles = list.files(mssdir, ".bsq$", recursive=T, full.names=T)
    tmcompfiles = list.files(tmdir, ".bsq$", recursive=T, full.names=T)
    thesetm = which(basename(tmcompfiles) %in% basename(msscompfiles))
    overlaptmfiles = sort(tmcompfiles[thesetm])
    thesemss = which(basename(msscompfiles) %in% basename(tmcompfiles))
    overlapmssfiles = sort(msscompfiles[thesemss])
    for(i in 1:length(overlapmssfiles)){
      mssr= raster(overlapmssfiles[i])
      mssrnas = which(values(mssr)==0)
      mssr[mssrnas] = NA
      tmr= raster(overlaptmfiles[i])
      tmrnas = which(values(tmr)==0)
      tmr[tmrnas] = NA
      newimg = mosaic(mssr,tmr, fun="mean", na.rm=T)
      combnas = c(mssrnas, tmrnas)
      newimg[combnas] = 0
      projection(newimg) = set_projection(files[1])
      
      outimgfile = file.path(outdir,basename(overlapmssfiles[i]))
      writeRaster(newimg, outimgfile, format="ENVI", datatype = "INT2S",overwrite=T)
      envifilename = sub("bsq","envi",outimgfile)
      envixmlfile = paste(envifilename,".aux.xml",sep="")
      bsqxmlfile = sub("envi","bsq",envixmlfile)
      file.rename(envifilename,outimgfile)
      file.rename(envixmlfile,bsqxmlfile)
#       newimg = as(newimg, "SpatialGridDataFrame") #convert the raster to SGHF so it can be written using GDAL (faster than writing it with the raster package)
#       outimgfile = file.path(outdir,basename(overlapmssfiles[i]))
#       writeGDAL(newimg, outimgfile, drivername = "ENVI", type = "Int16", mvFlag = -32768) #, options="INTERLEAVE=BAND"
    }
    
    #rename files
    print("directory and file organization/cleaning")
    msstmfiles = c(msscompfiles,tmcompfiles)
    finalfiles = file.path(outdir,basename(msstmfiles))
    imglists = list.files = list.files(offsetdir, "composite_img_list.csv", recursive=T, full.names=T)
    imglistyears = substr(basename(imglists),1,4)
    uniimglistyears = unique(imglistyears)
    for(i in 1:length(uniimglistyears)){
      theseimgslists = which(imglistyears == uniimglistyears[i])
      data1 = read.csv(imglists[theseimgslists[1]])
      data2 = read.csv(imglists[theseimgslists[2]])
      mergedlists = as.data.frame(rbind(data1,data2)$File)
      colnames(mergedlists) = "File"
      outname = file.path(outdir,paste(uniimglistyears[i],"_",runname,"_",index,"_composite_img_list.csv", sep=""))
      write.csv(mergedlists,outname)
    }
    for(i in 1:length(finalfiles)){
      check = file.exists(finalfiles[i])
      if(check == F){
        year = substr(basename(finalfiles[i]),1,4)
        files = list.files(dirname(msstmfiles[i]),year,full.names=T)
        file.rename(files,file.path(outdir,basename(files)))
      }
    }
    
    #clean up
    unlink(c(mssdir,tmdir), recursive=T)
  }
  
  print("making final annual composite stack")
  bname = paste(runname,"_",index,"_composite_stack.bsq", sep="")
  bands = sort(list.files(outdir, "composite.bsq$", full.names=T))
  fullnametif = file.path(outdir,bname)
  fullnamevrt = sub(".bsq", ".vrt", fullnametif)
  gdalbuildvrt(gdalfile=bands, output.vrt = fullnamevrt, separate=T) #, tr=c(reso,reso)
  gdal_translate(src_dataset=fullnamevrt, dst_dataset=fullnametif, of = "ENVI") #, co="INTERLEAVE=BAND"
  unlink(fullnamevrt)
}


