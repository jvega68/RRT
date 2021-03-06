#' Download R packages from the MRAN server
#' 
#' This function uses rsync, which is faster than the method (wget) \code{install.packages} uses 
#' by default. This function does not install packages, but only downloads them to your machine.
#'
#' @importFrom plyr rbind.fill
#' @export
#' @param date Date as "year-month-day" (YY-MM-DD)
#' @param snapshotid Optional. You can give the exact snapshot ID insetad of a date.
#' @param outdir Output directory
#' @param pkgs Packages to install with version numbers, e.g. plyr_1.8.1
#' @examples \dontrun{
#' # By default installs most recent version
#' pkgs_mran(date='2014-06-19', pkgs=c("plyr","ggplot2"), outdir="~/mran_snaps/")
#'
#' pkgs_mran(date='2014-06-19', pkgs=c("plyr_1.8.1","ggplot2_1.0.0"), outdir="~/mran_snaps/stuff/")
#' pkgs_mran(date='2014-06-19', pkgs="rgbif_0.6.2", outdir="~/mran_snaps/stuff/")
#' }

pkgs_mran <- function(date=NULL, snapshotid=NULL, pkgs=NULL, outdir=NULL)
{
  if(is.null(outdir)) stop("You must specify a directory to download packages to")
  if(is.null(pkgs)) stop("You must specify one or more packages to get")

  # get available snapshots
  snapshot_use <- if(is.null(snapshotid)) getsnapshotid(date) else snapshotid

  # parse versions from pkgs
  foo <- function(x){
    vers <- tryCatch(mran_pkg_avail(snapshot=snapshot_use, package=x[[1]]), error=function(e) e)
    if("error" %in% class(vers)){
      sprintf("%s/__notfound__", x[[1]])
    } else {    
      splitvers <- vapply(vers, strsplit, list(1), "\\.")
      df <- data.frame(do.call(rbind.fill, lapply(splitvers, function(x) data.frame(rbind(x), stringsAsFactors = FALSE))), stringsAsFactors = FALSE)
      df[is.na(df)] <- 0
      row.names(df) <- names(splitvers)
      df <- suppressWarnings(colClasses(df, "numeric"))
      if(NCOL(df) == 3){ df <- sort_df(df, c("X1","X2","X3")) } else {
        df <- sort_df(df, c("X1","X2"))      
      }
      pkgver <- tryCatch(x[[2]], error=function(e) e)
      if('error' %in% class(pkgver)) {
        pkgveruse <- row.names(df[nrow(df),])
      } else {
        pkgveruse <- if(pkgver %in% vers) pkgver else unname(verssorted[length(verssorted)])
      }
      sprintf("%s/%s_%s.tar.gz", x[[1]], x[[1]], pkgveruse)
    }
  }

  pkgs <- lapply(pkgs, function(x) strsplit(x, "_")[[1]])
  pkgpaths <- sapply(pkgs, foo)

  notonmran <- grep("__notfound__", pkgpaths, value = TRUE)
  pkgpaths <- pkgpaths[!grepl("__notfound__", pkgpaths)]
  
  if(length(notonmran) > 0) {
    gg <- vapply(notonmran, function(x) strsplit(x, "/")[[1]][[1]], character(1), USE.NAMES = FALSE)
    message(sprintf("Not found on MRAN:\n%s", paste0(gg, collapse = ", "))) 
  }
  
  tmppkgsfileloc <- tempfile()
  cat(pkgpaths, file = tmppkgsfileloc, sep = "\n")
  cmd <- sprintf('rsync -rt --progress --files-from=%s marmoset.revolutionanalytics.com::MRAN-snapshots/%s %s',
                 tmppkgsfileloc, snapshot_use, outdir)
  setwd(outdir)
  mvcmd <- sprintf("mv %s .", paste(pkgpaths, collapse = " "))
  rmcmd <- sprintf("rm -rf %s", paste(sapply(pkgpaths, function(x) strsplit(x, "/")[[1]][[1]], USE.NAMES = FALSE), collapse = " "))
  system(cmd)
  system(mvcmd)
  system(rmcmd)
  tools::write_PACKAGES(outdir)
}


colClasses <- function (d, colClasses)
{
  colClasses <- rep(colClasses, len = length(d))
  d[] <- lapply(seq_along(d), function(i) switch(colClasses[i],
            numeric = as.numeric(d[[i]]), character = as.character(d[[i]]),
            Date = as.Date(d[[i]], origin = "1970-01-01"), POSIXct = as.POSIXct(d[[i]],
                  origin = "1970-01-01"), factor = as.factor(d[[i]]),
            as(d[[i]], colClasses[i])))
  d
}

sort_df <- function (data, vars = names(data)){
  if (length(vars) == 0 || is.null(vars))
    return(data)
  data[do.call("order", data[, vars, drop = FALSE]), , drop = FALSE]
}

getsnapshotid <- function(date){
  # get available snapshots
  availsnaps <- suppressMessages(mran_snaps())
  
  if(is.null(date)) date <- Sys.Date()
  snapshots <- grep(date, availsnaps, value = TRUE)
  if(length(snapshots) > 1){
    print(data.frame(snapshots))
    message("\nMore than one snapshot matching your date found \n",
            "Enter rownumber of snapshot (other inputs will return 'NA'):\n")
    take <- scan(n = 1, quiet = TRUE, what = 'raw')
    if(is.na(take)){ message("No snapshot found or you didn't select one") }
    snapshots[as.numeric(take)]
  } else { snapshots }
}