
# Create users


    sudo ./bin/rvd_back.pl --add-user=username

    sudo ./bin/rvd_back.pl --add-user-ldap=username


# Import KVM virtual machines.

Usually, virtual machines are created within ravada, but they can be
imported from existing KVM domains. Once the domain is created :

    sudo ./bin/rvd_back.pl --import-domain=a

It will ask the name of the user the domain will be owned by.


# View all rvd_back options

In order to manage your backend easily, rvd_back has a few flags that
lets you made different things (like changing the password for an user).

If you want to view the full list, execute:

    sudo rvd_back --help

# Admin

## Create Virtual Machine

Go to Admin -> Machines and press _New Machine_ button.

If anything goes wrong check Admin -> Messages for information
from the Ravada backend.

## ISO MD5 missmatch

When downloading the ISO, it may fail or get old. Check the error
message for the name of the ISO file and the ID.

* Remove the ISO file shown at the error message
* Clean the MD5 entry in the database:

    mysql -u rvd_user -p ravada
    mysql> update iso_images set md5='' WHERE id=_ID_

Then you have to create the machine from scratch, nothing has been done.
