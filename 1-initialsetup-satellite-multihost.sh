#!/bin/bash

# Parameters that can be changed, or passed in. Hard coded for testing purposes.
ORG=ORGNAME
MAIN_LOC=LOCNAME
OFFERED_OS=("rhel8" "rhel9" "rhel10")
TENANT_LOCS=("LOC1" "LOC2") 
PROMOTION_PATHS=("canary" "test" "prod" "dev")
DEFAULT_CONTENT_VIEW="Default Organization View"

# Check if the organisation object exists, create it if not
id=`hammer organization info --name $ORG --fields id`

# Look at a host group. Check if it's a member of the organisation that we want
# it to be part of. If yes - do nothing. If no - add it, without clobbering
# any existing organisation memberships.
#
# Parameters:
#   $1 - the title of the hostgroup. (Not the name - the fully qualified title.)
#   $2 - the organisation ID that it should belong to.
function update_hostgroup () {
  local x
  local have_match
  local new_org_ids
  local i 
  #   Example hammer command to update the hostgroup:
  #   hammer --output json hostgroup info --title $titlename
  x=`hammer --output json hostgroup info --title $1|jq '.Organizations[].Id'`
  have_match=false
  new_org_ids="$2"
  for i in $x; do
    if [ $i -eq $2 ]; then
      have_match=true
      return
    else
      new_org_ids="$i,$new_org_ids"
    fi
  done

  # Note that we've been building up $new_org_ids by pre-pending membership
  # IDs, followed by a comma, starting with just the organisation that the
  # host group should be a member of. Thus, $new_org_ids will be exactly the
  # list of organisations the group should be in.
  if [ $have_match = "false" ]; then
    #   Example hammer command to update hg:
    #   hammer --output json hostgroup info --title $title
    hammer hostgroup update --title $1 --organization-ids "$new_org_ids"
  else
    echo "We should never get here."
  fi
}

if [ -z "$id" ]; then
  #   Example hammer command to create org:
  #   hammer organization create --name "$ORG"
  hammer organization create --name "$ORG"
  id=`hammer organization info --name $ORG --fields id`
fi

# Grab the organisation ID; it's significantly easier to work with that than the string name.
org_id=`echo $id|sed -e 's+^Id: ++'`

# Check for the main location, create it if it's not there.
# Note: The check-create-check-get-ID pattern is very common.
# To do: separate that pattern into a function for neatness.
#   Example hammer command to verify loc:
#   hammer location info --name $MAIN_LOC --fields id
id=`hammer location info --name $MAIN_LOC --fields id`
if [ -z "$id" ]; then
  #   example Hammer command to create loc:
  #   hammer location create --name $MAIN_LOC
  hammer location create --name $MAIN_LOC
  id=`hammer location info --name $MAIN_LOC --fields id`
fi

loc_id=`echo $id|sed -e 's+^Id: ++'`

# Get the Library LCE for the organisation.
i
# Example hammer command to find an LCE (library in this case):
# hammer lifecycle-environment info --name Library --organization-id $org_id --fields id
id=`hammer lifecycle-environment info --name Library --organization-id $org_id --fields id`
lib_lce_id=`echo $id|sed -e 's+^Id: ++'`

# Loop through the operating systems that we want to offer.
for os in ${OFFERED_OS[*]}; do
  # For each operating system, create a hg-OS. LCE at this level is Library.
  # The hg_OS group might already exist in a different organisation, in which
  # case, extend it to our organisation.
  #   Example hammer command to find info on hg:
  #   hammer hostgroup info --title hg_$os --fields id
  id=`hammer hostgroup info --title hg_$os --fields id`
  if [ -z "$id" ]; then
    hammer hostgroup create --name hg_$os --organization-id $org_id
    id=`hammer hostgroup info --title hg_$os --fields id`
  else
    update_hostgroup hg_$os $org_id
    #x=`hammer --output json hostgroup info --title hg_$os|jq '.Organizations[].Id'`
    #have_match=false
    #new_org_ids=''
    #for i in $x; do
    #  if [ $i -eq $org_id ]; then
    #    have_match=true
    #  else
    #    new_org_ids="$i,$new_org_ids"
    #  fi
    #done
    #if [ $have_match="false" ]; then
    #  # Update the hostgroup to also be visible to this organisation.
    #  hammer hostgroup update --title hg_$os --organization-ids "$new_org_ids"$org_id
    #fi
  fi

  parent_name=hg_$os

  hg_os_id=`echo $id|sed -e 's+^Id: ++'`

  # Look for the cv_OS content view and get its ID if it exists. If it doesn't exist,
  # use the default content view.
  #   Example hammer command to interrogate content views:
  #   hammer content-view info --name cv_$os --organization-id $org_id --fields id
  id=`hammer content-view info --name cv_$os --organization-id $org_id --fields id`
  if [ -z "$id" ]; then
    # Example hammer command to grab field IPs:
    id=`hammer content-view info --name "$DEFAULT_CONTENT_VIEW" --organization-id $org_id --fields id`
  fi
  cv_os_id=`echo $id|sed -e 's+^Id: ++'`

  # Now create the sub-locations for each operating system cv.
  for loc in ${TENANT_LOCS[*]}; do
    id=`hammer hostgroup info --title $parent_name/hg_$loc --fields id`
    if [ -z "$id" ]; then
      # Once again, lifecycle environment is Library at this level.
      hammer hostgroup create --content-view-id $cv_os_id --lifecycle-environment-id $lib_lce_id --location-id $loc_id --name hg_$loc --organization-id $org_id --parent-id $hg_os_id
      id=`hammer hostgroup info --title $parent_name/hg_$loc --fields id`
    else
      update_hostgroup $parent_name/hg_$loc $org_id
    fi

    hg_loc_id=`echo $id|sed -e 's+^Id: ++'`
    loc_parent_name=$parent_name/hg_$loc

    # Lastly: configure promotion paths in the LCE-specific hostgroup objects
    for prom in ${PROMOTION_PATHS[*]}; do
      # Find the LCE if it exists.
      #   Example hammer command to interrogate lce:
      #   hammer lifecycle-environment info --name lce_$prom --organization-id $org_id --fields id
      id=`hammer lifecycle-environment info --name lce_$prom --organization-id $org_id --fields id`
      if [ -z "$id" ]; then
        # Create, or default? For now: default
	# Placeholder (encountered local issue creating LCE; LCE creation to replace below line)
	id=`hammer lifecycle-environment info --name Library --organization-id $org_id --fields id`
      fi
      lce_id=`echo $id|sed -e 's+^Id: ++'`
      
      id=`hammer hostgroup info --title $loc_parent_name/hg_$prom --fields id`
      if [ -z "$id" ]; then
        #   Example hammer command to create nested hostgroup
        #   hammer hostgroup create --content-view-id $cv_os_id --lifecycle-environment-id $lce_id --location-id $loc_id --name hg_$prom --organization-id $org_id --parent-id $hg_loc_id
        hammer hostgroup create --content-view-id $cv_os_id --lifecycle-environment-id $lce_id --location-id $loc_id --name hg_$prom --organization-id $org_id --parent-id $hg_loc_id
      else
	# Use the update hostgroup function abve
        update_hostgroup $loc_parent_name/hg_$prom $org_id
      fi
    done
  done
done

