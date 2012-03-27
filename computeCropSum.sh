#!/usr/bin/env bash

# description---------------------------------------------------------

# Takes as input a *5yravg*.nc (or similar) from EPIC
# (possibly as modified by modifyDN2.r) containing one layer per crop, 
# and a single data variable (description).

# Outputs a new 5yravg.*.nc containing
# * only the desired datavar ...
# * ... with an additional layer showing where there's BELD data ...
# * ... and an additional layer containing the sum of the other layers.

# Requires
# 1 up-to-date R, with added (non-base) packages

# * 'ncdf4'

# http://cran.r-project.org/web/packages/ncdf4/
# http://cirrus.ucsd.edu/~pierce/ncdf/

# * 'M3'

# http://cran.r-project.org/web/packages/M3/

# * 'fields' (for plotting)

# http://www.image.ucar.edu/Software/Fields/

# 2 up-to-date NCO

# http://nco.sourceforge.net/

#   to do some file modification that's tedious to do with R
#   (but could almost certainly be done R-alone).

# 3 m3tools/m3wndw from

# http://www.baronams.com/products/ioapi/M3WNDW.html

#   to do the file windowing.

# 4 helper scripts

### TODO: FINISH ME###

# (It also uses

# * a PDF viewer to display produced plots:
#   edit the script to use your local tool of choice.

# * m3tools/m3stat from

# http://www.baronams.com/products/ioapi/M3STAT.html

#   for "IOAPI verification," though it's more slack than VERDI.

# These can be commented out if desired.)

# Overview:
# 1 (NCO) remove all datavars != DN2
# 2 (NCO) create new layers: extend datavar == DN2 along dim==LAY
# 3 (writeBELDlayer.r) mark each gridcell in BELD layer for which we have BELD data
# 4 (computeCropSum.r) in sum layer, compute sum of products of EPIC and BELD

# code----------------------------------------------------------------

# constants-----------------------------------------------------------

# TODO: take switches for help, debugging, no/eval, target drive
THIS="$0"
THIS_FN="$(basename $0)"
THIS_DIR="$(dirname $0)"

VAR_NAME="DN2"
DIM_RECORD="TSTEP" # name of the record dimension
DIM_TO_SUM="LAY"   # along which we want to sum
# Following is only required to make NCO happy:
# NCO requires datavars with attribute=missing_value to also have attribute=_FillValue
# TODO: find out how to get this programmatically!
VAR_MISSING_VALUE='-9.999e+36'
let N_LAYERS_TO_CREATE=2 # BELD and sum

BELD_TAG="12km_6_13_11_LimeiRan"
BELD_DIR="${THIS_DIR}"
# RDS is R serialization format
BELD_FN="BELD4crops_${BELD_TAG}.rds"
BELD_FP="${BELD_DIR}/${BELD_FN}"

EPIC_DIR="${THIS_DIR}"
# EPIC_ORIGINAL has
# + all the original fields
# - the monotonicization problem
# TODO: add demonotonicization to this script!
EPIC_ORIGINAL_FN="5yravg.test.nc"
EPIC_ORIGINAL_FP="${EPIC_DIR}/${EPIC_ORIGINAL_FN}"
EPIC_INPUT_FN="5yravg.fixed${VAR_NAME}.nc"
EPIC_INPUT_FP="${EPIC_DIR}/${EPIC_INPUT_FN}"
EPIC_STRIPPED_FN="5yravg.${VAR_NAME}stripped.nc"
EPIC_STRIPPED_FP="${EPIC_DIR}/${EPIC_STRIPPED_FN}"
EPIC_VARS_FIXED_FN="5yravg.${VAR_NAME}vars_fixed.nc"
EPIC_VARS_FIXED_FP="${EPIC_DIR}/${EPIC_VARS_FIXED_FN}"
EPIC_DEMONOTONICIZED_FN="5yravg.${VAR_NAME}demonotonicized.nc"
EPIC_DEMONOTONICIZED_FP="${EPIC_DIR}/${EPIC_DEMONOTONICIZED_FN}"
EPIC_TEMP_FULL_FN="temp.full.nc"
EPIC_TEMP_FULL_FP="${EPIC_DIR}/${EPIC_TEMP_FULL_FN}"
EPIC_TEMP_EXTEND_FN="temp.extend.nc"
EPIC_TEMP_EXTEND_FP="${EPIC_DIR}/${EPIC_TEMP_EXTEND_FN}"
EPIC_LAYERED_FN="5yravg.${VAR_NAME}layered.nc"
EPIC_LAYERED_FP="${EPIC_DIR}/${EPIC_LAYERED_FN}"
EPIC_LAYERS_FIXED_FN="5yravg.${VAR_NAME}layers_fixed.nc"
EPIC_LAYERS_FIXED_FP="${EPIC_DIR}/${EPIC_LAYERS_FIXED_FN}"
EPIC_BELDED_FN="5yravg.${VAR_NAME}belded.nc"
EPIC_BELDED_FP="${EPIC_DIR}/${EPIC_BELDED_FN}"
EPIC_SUMMED_FN="5yravg.${VAR_NAME}summed.nc"
EPIC_SUMMED_FP="${EPIC_DIR}/${EPIC_SUMMED_FN}"
EPIC_WINDOWED_FN="5yravg.${VAR_NAME}windowed.nc"
EPIC_WINDOWED_FP="${EPIC_DIR}/${EPIC_WINDOWED_FN}"

# Windowing:
# bounds:
# * order follows m3wndw input convention
# * all values signed decimal (i.e., S,W are negative)
let WEST_LON=-96
let EAST_LON=-90
let SOUTH_LAT=39
let NORTH_LAT=45
# input file for driving m3wndw 
M3WNDW_INPUT_FP="$(mktemp)"

# this fixes removed vars, and dims and global attributes that must reflect them
FIX_VARS_SCRIPT="${EPIC_DIR}/processVars.r"
# This script, which "demonotonocizes" a datavar, should become unnecessary with future EPIC data.
DEMONOTONICIZE_SCRIPT="${EPIC_DIR}/demonotonicizeVar.r"
# this fixes created layers, and global attributes that must reflect them
FIX_LAYERS_SCRIPT="${EPIC_DIR}/processLayers.r"
# this writes BELD layer (and plots, if desired)
BELD_SCRIPT="${EPIC_DIR}/writeBELDlayer.r"
# this sums (and plots, if desired)
SUM_SCRIPT="${EPIC_DIR}/computeCropSum.r"
# windows summed emissions to subdomain
WINDOW_SCRIPT="${EPIC_DIR}/windowEmissions.r"
# this plots layers for timestep(s)
PLOT_SCRIPT="${EPIC_DIR}/justPlots.r"
# plot to this
PDF_FP="${EPIC_DIR}/compare.DN2.layers.pdf"

# functions-----------------------------------------------------------

# If your computing platform uses Environment Modules (

# ), load modules for current NCO and IOAPI, noting
# how this syntax differs from the commandline.
# (Thanks, Barron Henderson for noting this.)
# TODO: test for non/existence of paths above!
function setup {
  # for CMD in \
  #   "modulecmd bash add nco ioapi-3.1" \
  # ; do
  #   echo -e "$ ${CMD}"
  #   eval "${CMD}"
  # done
  TEMPFILE="$(mktemp)"
  modulecmd bash add nco ioapi-3.1 > ${TEMPFILE}
  source ${TEMPFILE}
}

# for IOAPI, gotta keep var=TFLAG as well,
# *AND* gotta fix
# * coordinate var=VAR
# * global attr=VAR-LIST
#    "ncatted -O -a _FillValue,${VAR_NAME},o,f,${VAR_MISSING_VALUE} ${EPIC_STRIPPED_FP}" \
# Note I copy files to output, *then* work on them, because that's what
# R package=ncdf4 seems to want.
function stripOtherDatavars {
  TEMPFILE="$(mktemp)" # for R output
  # gotta quote the double quotes :-(
  # need EPIC_ORIGINAL_FP to get original TFLAG?
# epic.input.fp=\"${EPIC_ORIGINAL_FP}\" \
  for CMD in \
    "ncks -O -v ${VAR_NAME},TFLAG ${EPIC_ORIGINAL_FP} ${EPIC_STRIPPED_FP}" \
    "cp ${EPIC_STRIPPED_FP} ${EPIC_VARS_FIXED_FP}" \
    "R CMD BATCH --vanilla --slave '--args \
datavar.name=\"${VAR_NAME}\" \
plot.layers=FALSE \
epic.input.fp=\"${EPIC_STRIPPED_FP}\" \
epic.output.fp=\"${EPIC_VARS_FIXED_FP}\"' \
${FIX_VARS_SCRIPT} ${TEMPFILE}" \
    "cat ${TEMPFILE}" \
  ; do
    echo -e "$ ${CMD}"
    eval "${CMD}"
  done
#  ncdump -v TFLAG ${EPIC_VARS_FIXED_FP}
  export M3STAT_FILE="${EPIC_VARS_FIXED_FP}"
}

# This should become unnecessary with future EPIC data.
# TODO: test arguments
function demonotonicizeDatavar {
  TEMPFILE="$(mktemp)" # for R output
  # gotta quote the double quotes :-(
  for CMD in \
    "cp ${EPIC_VARS_FIXED_FP} ${EPIC_DEMONOTONICIZED_FP}" \
    "R CMD BATCH --vanilla --slave '--args \
datavar.name=\"${VAR_NAME}\" \
plot.layers=FALSE \
epic.input.fp=\"${EPIC_VARS_FIXED_FP}\" \
epic.output.fp=\"${EPIC_DEMONOTONICIZED_FP}\"' \
${DEMONOTONICIZE_SCRIPT} ${TEMPFILE}" \
    "cat ${TEMPFILE}" \
  ; do
    echo -e "$ ${CMD}"
    eval "${CMD}"
  done
  export M3STAT_FILE="${EPIC_DEMONOTONICIZED_FP}"
}

# Create a layer for BELD data, and a layer for emissions integration
function createLayers {
  for CMD in \
    "ncpdq -O -a ${DIM_TO_SUM},${DIM_RECORD} ${EPIC_DEMONOTONICIZED_FP} ${EPIC_TEMP_FULL_FP}" \
    "ncrcat -O -d ${DIM_TO_SUM},1,${N_LAYERS_TO_CREATE} ${EPIC_TEMP_FULL_FP} ${EPIC_TEMP_EXTEND_FP}" \
    "ncrcat -O ${EPIC_TEMP_FULL_FP} ${EPIC_TEMP_EXTEND_FP} ${EPIC_TEMP_FULL_FP}" \
    "ncpdq -O -a ${DIM_RECORD},${DIM_TO_SUM} ${EPIC_TEMP_FULL_FP} ${EPIC_LAYERED_FP}" \
  ; do
    echo -e "$ ${CMD}"
    eval "${CMD}"
  done
  # don't try to do `m3stat` until we process the layers
#  export M3STAT_FILE="${EPIC_LAYERED_FP}"
  # instead can do
#  ncdump -h ${EPIC_LAYERED_FP}
}

# Make file IOAPI-compliant (or at least enough for VERDI)
# TODO: test arguments
function processLayers {
  TEMPFILE="$(mktemp)" # for R output
  # gotta quote the double quotes :-(
  # but don't quote ${N_LAYERS_TO_CREATE}: becomes "non-numeric argument to binary operator"
  for CMD in \
    "cp ${EPIC_LAYERED_FP} ${EPIC_LAYERS_FIXED_FP}" \
    "R CMD BATCH --vanilla --slave '--args \
datavar.name=\"${VAR_NAME}\" \
plot.layers=FALSE \
layers.to.fix=${N_LAYERS_TO_CREATE} \
epic.input.fp=\"${EPIC_LAYERED_FP}\" \
epic.output.fp=\"${EPIC_LAYERS_FIXED_FP}\" ' \
${FIX_LAYERS_SCRIPT} ${TEMPFILE}" \
    "cat ${TEMPFILE}" \
  ; do
    echo -e "$ ${CMD}"
    eval "${CMD}"
  done
  export M3STAT_FILE="${EPIC_LAYERS_FIXED_FP}"
}

# Append a layer containing the sum of the BELD fractions.
# TODO: test arguments
function writeBELDlayer {
  TEMPFILE="$(mktemp)" # for R output
  # gotta quote the double quotes :-(
  for CMD in \
    "cp ${EPIC_LAYERS_FIXED_FP} ${EPIC_BELDED_FP} " \
    "R CMD BATCH --vanilla --slave '--args \
datavar.name=\"${VAR_NAME}\" \
plot.layers=FALSE \
epic.input.fp=\"${EPIC_LAYERS_FIXED_FP}\" \
beld.fp=\"${BELD_FP}\" \
epic.output.fp=\"${EPIC_BELDED_FP}\"' \
${BELD_SCRIPT} ${TEMPFILE}" \
    "cat ${TEMPFILE}" \
  ; do
    echo -e "$ ${CMD}"
    eval "${CMD}"
  done
  export M3STAT_FILE="${EPIC_BELDED_FP}"
}

# Append a layer containing the integrated emissions.
# TODO: test for arguments
function writeSumLayer {
  TEMPFILE="$(mktemp)" # for R output
  # gotta quote the double quotes :-(
  for CMD in \
    "cp ${EPIC_BELDED_FP} ${EPIC_SUMMED_FP}" \
    "R CMD BATCH --vanilla --slave '--args \
datavar.name=\"${VAR_NAME}\" \
plot.layers=FALSE \
epic.input.fp=\"${EPIC_BELDED_FP}\" \
beld.fp=\"${BELD_FP}\" \
epic.output.fp=\"${EPIC_SUMMED_FP}\" \
image.fp=\"${PDF_FP}\"' \
${SUM_SCRIPT} ${TEMPFILE}" \
    "cat ${TEMPFILE}" \
  ; do
    echo -e "$ ${CMD}"
    eval "${CMD}"
  done
  export M3STAT_FILE="${EPIC_SUMMED_FP}"
}

# Window the summed (or other) file prepared above
# TODO: test for arguments
function windowSummedFile {
  TEMPFILE="$(mktemp)" # for R output
  # These exports are needed by the R script.
  # EMPIRICAL NOTE:
  # m3wndw (perhaps all of m3tools) truncate envvars @ length=16!
  # e.g., "M3WNDW_INPUT_FILE" -> "M3WNDW_INPUT_FIL", which fails lookup.
  export M3WNDW_INFILE="${EPIC_SUMMED_FP}"
  export M3WNDW_OUTFILE="${EPIC_WINDOWED_FP}"
  # gotta quote the double quotes, and CANNOT HAVE SPACES IN ARGUMENTS :-(
  # so do following hoop-jumping to pass the m2wndw command string
  M3WNDW_COMMAND="m3wndw M3WNDW_INFILE M3WNDW_OUTFILE < ${M3WNDW_INPUT_FP}"
  M3WNDW_COMMAND_SPACE_REPLACER="+"
  # use bash string manipulation
  M3WNDW_COMMAND_SPACE_REPLACED="${M3WNDW_COMMAND// /${M3WNDW_COMMAND_SPACE_REPLACER}}"
  for CMD in \
    "R CMD BATCH --vanilla --slave '--args \
data.input.fp=\"${EPIC_SUMMED_FP}\" \
data.output.fp=\"${EPIC_WINDOWED_FP}\" \
window.bounds.latlon=c(${WEST_LON},${EAST_LON},${SOUTH_LAT},${NORTH_LAT}) \
m3wndw.input.fp=\"${M3WNDW_INPUT_FP}\" \
m3wndw.command.space.replacer=\"${M3WNDW_COMMAND_SPACE_REPLACER}\" \
m3wndw.command.space.replaced=\"${M3WNDW_COMMAND_SPACE_REPLACED}\" \
plot.layers=TRUE \
image.fp=\"${PDF_FP}\"' \
${WINDOW_SCRIPT} ${TEMPFILE}" \
    "cat ${TEMPFILE}" \
  ; do
    echo -e "$ ${CMD}"
    eval "${CMD}"
  done
  export M3STAT_FILE="${EPIC_WINDOWED_FP}"
}

function teardown {
  TERRAE_PDF_VIEW_CMD="xpdf ${PDF_FP}"
  # Now loading module=ioapi-3.1 (for `m3stat`) in `setup`
  # run m3tools/m3stat on the output: default input==rep('\n', 4)
  m3stat M3STAT_FILE <<EOF




EOF

  # display the plot
  for CMD in \
    "ls -alh ${PDF_FP}" \
    "${TERRAE_PDF_VIEW_CMD}" \
  ; do
    echo -e "$ ${CMD}"
    eval "${CMD}"
  done
}

# script--------------------------------------------------------------

# TODO: test for prereqs:
# * well-formed BELD array @ beld.fp
# * well-formed EPIC output @ epic.fp
# * NCO in path

#   "setup" \
#   "stripOtherDatavars" \
#   "demonotonicizeDatavar" \
#   "createLayers" \
#   "processLayers" \
#   "writeBELDlayer" \
#   "writeSumLayer" \
#   "windowSummedFile" \
#   "teardown" \
# should always
# * begin with `setup` to do `module add`
# * end with `teardown` to do output testing (e.g., plot display)
for CMD in \
  "setup" \
  "stripOtherDatavars" \
  "demonotonicizeDatavar" \
  "createLayers" \
  "processLayers" \
  "writeBELDlayer" \
  "writeSumLayer" \
  "windowSummedFile" \
  "teardown" \
; do
  echo -e "\n${CMD}"
  eval "${CMD}"
  ls -alth *.nc
done

# debugging-----------------------------------------------------------
