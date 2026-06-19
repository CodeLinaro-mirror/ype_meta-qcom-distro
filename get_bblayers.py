# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Generate the bblayers.conf file for the current build workspace
# emitted to stdout for simplicity.

import os, fnmatch, re, argparse
from operator import itemgetter

# Layers to be excluded
ignoreList = [  "meta-selftest", "meta-skeleton", \
                "meta-gplv2", \
                "meta-rust", \
                "meta-qcom-dpk", \
                "meta-qti-touch", \
                "meta-qti-voiceai", \
                "meta-qti-dpk", \
                "meta-qti-dpk-audio", \
                "meta-qti-dpk-camera", \
                "meta-qti-dpk-display", \
                "meta-qti-dpk-graphics", \
             ]

# Sub-layer info
MetaOeSubLayers        = [ "meta-networking", "meta-python", "meta-oe", \
                           "meta-filesystems", "meta-perl" , "meta-gnome", \
                           "meta-webserver", "meta-multimedia" ]

MetaSecuritySubLayers  = [ "meta-tpm" ]

MetaYoctoSubLayers     = [ "meta-poky" , "meta-yocto-bsp" ]

PokySubLayers          = [ "meta" , "meta-poky" ]

OeSubLayers            = [ "meta" ]

dicLayersWithSubLayers = { "meta-openembedded": MetaOeSubLayers, \
                           "meta-security": MetaSecuritySubLayers, \
                           "meta-yocto": MetaYoctoSubLayers, \
                           "openembedded-core": OeSubLayers, \
                           "poky": PokySubLayers, \
                         }

def getLayerCollections (layerConfPath) :
    # Open layer.conf file and find names of configured layer.
    confFile = open(layerConfPath, "r")
    if (confFile != None) :
        for line in confFile :
            fields = line.split()
            if (len(fields) > 0 and re.match("BBFILE_COLLECTIONS",  fields[0])) :
                #return name
                return fields[2].strip("\"")
    confFile.close()

def getLayerPriority (layerConfPath) :
    # Open layer.conf file and find the priority for it...
    confFile = open(layerConfPath, "r")
    if (confFile != None) :
        for line in confFile :
            fields = line.split()
            if (len(fields) > 0 and re.match("BBFILE_PRIORITY",  fields[0])) :
                #return priority
                return int(fields[2].strip("\""))
    confFile.close()

# Trawl the OEROOT as passed to us and find all the layer files that meet our
# metadata directory criteria...
def getLayerPaths(lookup,  fnexpr, checkname) :
    global ignoreList
    global dicLayersWithSubLayers
    retList = []
    for target in lookup:
        if os.path.exists(target):
            for file in os.listdir(target) :
                if not any(fnmatch.fnmatch(file, fnexpr) for fnexpr in ignoreList):
                    # Found what might be a valid metadata layer...
                    layerPath = target + "/" + file
                    layerConfPath = layerPath + "/conf/layer.conf"
                    if os.path.exists(layerConfPath) :
                        #Ignore qti layers not following naming convension
                        if (checkname and re.match("(.*?)meta-qti(.*?)", layerConfPath)) :
                            if not re.match("qti(-[a-zA-Z]+)+", getLayerCollections(layerConfPath)) :
                                print ("# Ignored for not following qti naming convention: " + \
                                    layerConfPath + " (" + getLayerCollections(layerConfPath) + ")")
                                continue
                        # Found a layer.  Find the priority for it...
                        retList += [( layerPath,  getLayerPriority (layerConfPath) )]
                    # Add layers that have sublayers
                    if (file in dicLayersWithSubLayers.keys()):
                        for subLayer in dicLayersWithSubLayers[file]:
                            path = layerPath + "/" + subLayer
                            if os.path.exists(path):
                                retList += [( path, getLayerPriority(path + "/conf/layer.conf") )]
    # In order to avoid potential namespace conflicts, between recipes on layers
    # we sort the list in descending order of priority.
    return sorted(retList,  key=itemgetter(1), reverse=True)

# Just spool the tuple list's paths out in order to a string...
def generatePathString ( pathList ):
    retString = " \\\n"
    for path, priority in pathList:
        retString = retString + "\t" + path + " \\\n"
    return retString

parser = argparse.ArgumentParser(description="Tool to generate the bblayers.conf for current build workspace",
        add_help=False)
parser.add_argument('layers', metavar='LAYERS', type=str, help='Layers to add')
parser.add_argument('--lookup-paths', default="none", dest='lookup_paths', nargs='*',
                   help='Look for meta layers from the given paths')
parser.add_argument('--with-layer-check', action='store_true', default=False, dest='check_layers',
                   help='check if qti meta layers following naming conventions (off by default)')
args = parser.parse_args()

# Emit our config file...
print ("# This configuration file is dynamically generated every time")
print ("# set_bb_env.sh is sourced to set up a workspace.  DO NOT EDIT.")
print ("#--------------------------------------------------------------")
print ("LCONF_VERSION = \"7\"\n")
print ("BBPATH = \"${TOPDIR}\"\n")
print ("BBFILES ?= \"\"\n")
print ("BBLAYERS = \"" + generatePathString(getLayerPaths(args.lookup_paths, args.layers.strip("\""), args.check_layers)) + "\"")
