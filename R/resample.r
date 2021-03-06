#' Resamples MSS dos_sr and cloudmask images to 30m
#'
#' Resamples MSS dos_sr and cloudmask images to 30m
#' @param file character. full path to either an MSS *reflectance.tif or *cloudmask.tif file
#' @import gdalUtils
#' @export

resample = function(file){
  type = c(length(grep("dos_sr", file)), length(grep("cloudmask", file)))
  
  if(type[1] == 1){
    newfile = sub("dos_sr", "dos_sr_30m", file)
    if(file.exists(newfile)==T){return()}
    gdalwarp(srcfile=file, dstfile=newfile,tr=c(30,30),
             srcnodata=-32768, dstnodata=-32768, multi=T)
  }
  if(type[2] == 1){
    newfile = sub("cloudmask", "cloudmask_30m", file)
    if(file.exists(newfile)==T){return()}
    gdalwarp(srcfile=file, dstfile=newfile,tr=c(30,30),
             srcnodata=255, dstnodata=255, multi=T)
  }
}

