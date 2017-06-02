Install Ravada 
==============

Requirements
------------

OS
--

Ravada has been successfully tested only on Ubuntu 16.10 and 17.04. It should also work in
recent RedHat based systems. Debian jessie has been tried but kvm spice
wasn't available there, so it won't work.

Hardware
--------

It depends on the number and the type of the virtual machines. For most
places

Memory
~~~~~~

RAM is the main issue. Multiply the number of concurrent workstations by
the amount of memory each one requires and that is the total RAM the server
must have.

Disks
~~~~~

The faster the disks, the better. Ravada uses incremental files for the
disks images, so clones won't require many space.

Install Ravada
--------------

Ubuntu
------

We provide *deb* Ubuntu packages. Download it from the `UPC ETSETB
repository <http://infoteleco.upc.edu/img/debian/>`__. Download and
install them:

::

    $ wget http://infoteleco.upc.edu/img/debian/libmojolicious-plugin-renderfile-perl_0.10-1_all.deb
    $ wget http://infoteleco.upc.edu/img/debian/ravada_0.2.7_all.deb
    $ sudo dpkg -i libmojolicious-plugin-renderfile-perl_0.10-1_all.deb
    $ sudo dpkg -i ravada_0.2.7_all.deb

The last command will show a warning about missing dependencies. Install
them running:

::

    $ sudo apt-get update
    $ sudo apt-get -f install

Development Release
-------------------

Read
`Development Release <http://ravada.readthedocs.io/en/latest/docs/INSTALL_devel.html>`__
if you want to develop Ravada or install a bleeding edge, non-packaged, release.

Mysql Database
--------------

MySQL server
~~~~~~~~~~~~
.. Warning::  MySql required minimum version 5.6

It is required a MySQL server, it can be installed in another host or in
the same one as the ravada package.

::

    $ sudo apt-get install mysql-server

MySQL user
~~~~~~~~~~

Create a database named "ravada". in this stage the system wants you to
identify a password for your sql.

::

    $ mysqladmin -u root -p create ravada

Grant all permissions to your user:

::

    $ mysql -u root -p ravada -e "grant all on ravada.* to rvd_user@'localhost' identified by 'CHOOSE A PASSWORD'"

Config file
~~~~~~~~~~~

Create a config file at /etc/ravada.conf with the username and password
you just declared at the previous step. Please note that you need to
edit the user and password via an editor. Here, we present Vi as an
example.

::

    $ sudo vi /etc/ravada.conf
    db:
      user: rvd_user
      password: THE PASSWORD CHOSEN BEFORE

Ravada web user
---------------

Add a new user for the ravada web. Use rvd\_back to create it.

::

    $ sudo /usr/sbin/rvd_back --add-user user.name

Firewall (Optional)
-------------------

The server must be able to send *DHCP* packets to its own virtual interface.

KVM should be using a virtual interface for the NAT domnains. Look what is the address range and add it to your *iptables* configuration.

First we try to find out what is the new internal network:

::

    $  sudo route -n
    ...
    192.168.122.0   0.0.0.0         255.255.255.0   U     0      0        0 virbr0

So it is 192.168.122.0 , netmask 24. Add it to your iptables configuration:

::

    sudo iptables -A INPUT -s 192.168.122.0/24 -p udp --dport 67:68 --sport 67:68 -j ACCEPT

To confirm that the configuration was updated, check it with:

::

    sudo iptables -S

Client
------

The client must have a spice viewer such as virt-viewer. There is a
package for linux and it can also be downloaded for windows.

Next
----

Read
`Running Ravada in production <http://ravada.readthedocs.io/en/latest/docs/production.html>`__.
