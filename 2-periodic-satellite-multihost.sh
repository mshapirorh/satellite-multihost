#!/usr/bin/bash -x

PUBLISH_VERSION=true

# TODO: turn into list to loop promotes over ansible-side
PROMOTE_TO_ENV=canary

ORG_NAME=sjl_test

# Get the date in YYYY-MM-DD format.
current_date=`date -I`

echo Getting organisation ID..
id=`hammer organization info --name $ORG_NAME --fields id`
echo Got organisation ID.
org_id=`echo $id|sed -e 's+^Id: ++'`

#for os in rhel8 rhel9 rhel10; do
for os in rhel9; do
  cv=cv_$os

  echo Getting CV ID for $cv..
  # Example hammer command to obtain CV IDs:
  # id=`hammer content-view info --organization-id $org_id --name $cv --fields id`
  id=`hammer content-view info --organization-id $org_id --name $cv --fields id`
  echo Got CV ID for $cv.
  cv_id=`echo $id|sed -e 's+^Id: ++'`

  # Look for the RPM filter.
  echo Getting RPM filter ID..
  # Example command to obtain filter list:
  # hammer --output json content-view filter list --content-view-id $cv_id --types rpm --fields 'filter id'
  #
  # Sample output:
  # [
  #   {
  #     "Filter ID": 10
  #   }
  # ]

  rpm_filter_ids=`hammer --output json content-view filter list --content-view-id $cv_id --types rpm --fields 'filter id'|jq '.[]."Filter ID"'`
  echo Got RPM filter ID.

  # XXX: rpm_filter_ids now holds ALL the RPM filters; we're assuming that
  # there is only one. More than one might cause this script to break.

  # XXX: For the packages-not-in-any-errata filter, need to get the original_packages value for the filter. This is only
  # available through the API, not from hammer.

  # XXX: Once we have that value, check that it's set to true for at least one
  # RPM filter.

  if [ $PUBLISH_VERSION = "true" ]; then
    echo Getting erratum filter ID...
    # Example command to list filter IDs: 
    # hammer --output json content-view filter list --content-view-id $cv_id --types erratum --fields 'filter id' --name filter_periodically_updates

    # Because we're looking for a specific filter name, there should be only one.
    erratum_filter_id=`hammer --output json content-view filter list --content-view-id $cv_id --types erratum --fields 'filter id' --name filter_periodically_updates|jq '.[]."Filter ID"'`
    echo Got erratum filter IDs.

    echo Getting rule IDs...
    rule_ids=`hammer --output json content-view filter rule list --content-view-filter-id $erratum_filter_id|jq '.[]."Rule ID"'`
    echo Got rule IDs.
    for j in $rule_ids; do
      echo Updating rule ID $j ...
      # Example command to update the filter end date:
      # hammer content-view filter rule update --content-view-filter-id $erratum_filter_id --id $j --end-date $current_date
      hammer content-view filter rule update --content-view-filter-id $erratum_filter_id --id $j --end-date $current_date
      echo Updated.
    done

    echo Publishing...
    # Example hammer command to publish the content view:
    # hammer content-view publish --id $cv_id
    hammer content-view publish --id $cv_id
    success=$?
    echo Published.
  fi

  if [ $PUBLISH_VERSION != "true" -o "$success" = "0" ]; then
    # Either we're publishing and it was successful, or we're not publishing. Either way, get the highest
    # version ID, which should be the latest version.
    echo Getting latest version..
    # Example hammer command we can use to identify recent published CV (Happy path): 
    # hammer --output json content-view version list --content-view-id $cv_id
    latest_version=`hammer --output json content-view version list --content-view-id $cv_id|jq '.[].Id'|sort -n|tail -1`
    echo Got it.

    if [ "$PROMOTE_TO_ENV" != "" ]; then
      echo Promoting to $PROMOTE_TO_ENV..
      # Example hammer command to promote the Content View Version that just got published:
      # hammer content-view version promote --content-view-id $cv_id --id $latest_version --to-lifecycle-environment "lce_$PROMOTE_TO_ENV" --organization-id $org_id
      echo hammer content-view version promote --content-view-id $cv_id --id $latest_version --to-lifecycle-environment "lce_$PROMOTE_TO_ENV" --organization-id $org_id
      hammer content-view version promote --content-view-id $cv_id --id $latest_version --to-lifecycle-environment "lce_$PROMOTE_TO_ENV" --organization-id $org_id
      echo Done.
    fi
  else
    # Unhappy path: we're publishing, it was unsuccessful for an unknown reason.
    # XXX
    true
  fi
done

