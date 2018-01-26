package Test::Ravada;
use strict;
use warnings;

use  Carp qw(carp confess);
use  Data::Dumper;
use Hash::Util qw(lock_hash);
use IPC::Run3 qw(run3);
use  Test::More;
use YAML qw(LoadFile);

eval {
    require Rex;
    Rex->import();

#    require Rex::Commands;
#    Rex::Commands->import;

    require Rex::Commands::Run;
    Rex::Commands::Run->import();

    require Rex::Group::Entry::Server;
    Rex::Group::Entry::Server->import();

    require Rex::Commands::Iptables;
    Rex::Commands::Iptables->import();

    require Rex::Commands::Run;
    Rex::Commands::Run->import();
};
our $REX_ERROR = $@;
warn $REX_ERROR if $REX_ERROR;

use feature qw(signatures);
no warnings "experimental::signatures";

use Ravada;
use Ravada::Auth::SQL;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

require Exporter;

@ISA = qw(Exporter);

@EXPORT = qw(base_domain_name new_domain_name rvd_back remove_old_disks remove_old_domains create_user user_admin wait_request rvd_front init init_vm clean new_pool_name
create_domain
    test_chain_prerouting
    search_id_iso
    flush_rules open_ipt
    remote_config
    remote_config_nodes
    clean_remote_node
    arg_create_dom
    vm_names
    search_iptable_remote
    clean_remote
    start_node shutdown_node remove_node
    start_domain_internal   shutdown_domain_internal
    arg_create_dom
    vm_names
);

our $DEFAULT_CONFIG = "t/etc/ravada.conf";
our $FILE_CONFIG_REMOTE = "t/etc/remote_vm.conf";

our ($CONNECTOR, $CONFIG);

our $CONT = 0;
our $CONT_POOL= 0;
our $USER_ADMIN;
our $CHAIN = 'RAVADA';

our %ARG_CREATE_DOM = (
    KVM => []
    ,Void => []
);

sub user_admin {
    return $USER_ADMIN;
}

sub arg_create_dom {
    my $vm_name = shift;
    confess "Unknown vm $vm_name"
        if !$ARG_CREATE_DOM{$vm_name};
    return @{$ARG_CREATE_DOM{$vm_name}};
}

sub vm_names {
    return sort keys %ARG_CREATE_DOM;
}

sub create_domain {
    my $vm_name = shift;
    my $user = (shift or $USER_ADMIN);
    my $id_iso = (shift or 'Alpine');

    if ( $id_iso && $id_iso !~ /^\d+$/) {
        my $iso_name = $id_iso;
        $id_iso = search_id_iso($iso_name);
        warn "I can't find iso $iso_name" if !defined $id_iso;
    }
    my $vm;
    if (ref($vm_name)) {
        $vm = $vm_name;
        $vm_name = $vm->type;
    } else {
        $vm = rvd_back()->search_vm($vm_name);
        ok($vm,"Expecting VM $vm_name, got ".$vm->type) or return;
    }

    confess "ERROR: Domains can only be created at localhost"
        if $vm->host ne 'localhost';
    confess "Missing id_iso" if !defined $id_iso;

    my $name = new_domain_name();

    my %arg_create = (id_iso => $id_iso);

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $user->id
                    , %arg_create
                    , active => 0
                    , memory => 256*1024
           );
    };
    is($@,'');

    return $domain;

}

sub base_domain_name {
    my ($name) = $0 =~ m{.*?/(.*)\.t};
    die "I can't find name in $0"   if !$name;
    $name =~ s{/}{_}g;

    return "tst_$name";
}

sub base_pool_name {
    my ($name) = $0 =~ m{.*?/(.*)\.t};
    die "I can't find name in $0"   if !$name;
    $name =~ s{/}{_}g;

    return "test_$name";
}

sub new_domain_name {
    return base_domain_name()."_".$CONT++;
}

sub new_pool_name {
    return base_pool_name()."_".$CONT_POOL++;
}

sub rvd_back {
    my ($connector, $config) = @_;
    init($connector,$config,0)    if $connector;

    my $rvd = Ravada->new(
            connector => $CONNECTOR
                , config => ( $CONFIG or $DEFAULT_CONFIG)
                , warn_error => 0
    );
    $rvd->_update_isos();
    $USER_ADMIN = create_user('admin','admin',1)    if !$USER_ADMIN;

    $ARG_CREATE_DOM{KVM} = [ id_iso => search_id_iso('Alpine') ];

    return $rvd;
}

sub rvd_front {

    return Ravada::Front->new(
            connector => $CONNECTOR
                , config => ( $CONFIG or $DEFAULT_CONFIG)
    );
}

sub init {
    my $create_user;
    ($CONNECTOR, $CONFIG, $create_user) = @_;

    $create_user = 1 if !defined $create_user;

    confess "Missing connector : init(\$connector,\$config)" if !$CONNECTOR;

    $Ravada::CONNECTOR = $CONNECTOR if !$Ravada::CONNECTOR;
    Ravada::Auth::SQL::_init_connector($CONNECTOR);
    $USER_ADMIN = create_user('admin','admin',1)    if $create_user;

    $Ravada::Domain::MIN_FREE_MEMORY = 512*1024;

<<<<<<< HEAD
}

sub remote_config {
    my $vm_name = shift;
    return { } if !-e $FILE_CONFIG_REMOTE;

    my $conf;
    eval { $conf = LoadFile($FILE_CONFIG_REMOTE) };
    is($@,'',"Error in $FILE_CONFIG_REMOTE\n".$@) or return;

    my $remote_conf = $conf->{$vm_name} or do {
        diag("SKIPPED: No $vm_name section in $FILE_CONFIG_REMOTE");
        return ;
    };
    for my $field ( qw(host user password security public_ip name)) {
        delete $remote_conf->{$field};
    }
    die "Unknown fields in remote_conf $vm_name, valids are : host user password name\n"
        .Dumper($remote_conf)   if keys %$remote_conf;

    $remote_conf = LoadFile($FILE_CONFIG_REMOTE);
    ok($remote_conf->{public_ip} ne $remote_conf->{host},
            "Public IP must be different from host at $FILE_CONFIG_REMOTE")
        if defined $remote_conf->{public_ip};

    $remote_conf->{public_ip} = '' if !exists $remote_conf->{public_ip};

    lock_hash(%$remote_conf);
    return $remote_conf->{$vm_name};
}

sub remote_config_nodes {
    my $file_config = shift;
    confess "Missing file $file_config" if !-e $file_config;

    my $conf;
    eval { $conf = LoadFile($file_config) };
    is($@,'',"Error in $file_config\n".($@ or ''))  or return;

    lock_hash((%$conf));

    for my $name (keys %$conf) {
        if ( !$conf->{$name}->{host} ) {
            warn "ERROR: Missing host section in ".Dumper($conf->{$name})
                ."at $file_config\n";
            next;
        }
    }
    return $conf;
=======
>>>>>>> master
}

sub _remove_old_domains_vm {
    my $vm_name = shift;

    my $domain;

    my $vm;

    if (ref($vm_name)) {
        $vm = $vm_name;
    } else {
        eval {
        my $rvd_back=rvd_back();
        return if !$rvd_back;
        $vm = $rvd_back->search_vm($vm_name);
        };
        diag($@) if $@;

        return if !$vm;
    }
    my $base_name = base_domain_name();

    my @domains;
    eval { @domains = $vm->list_domains() };
    for my $domain ( sort { $b->name cmp $a->name }  @domains) {
        next if $domain->name !~ /^$base_name/i;

        eval { $domain->shutdown_now($USER_ADMIN); };
        warn "Error shutdown ".$domain->name." $@" if $@ && $@ !~ /No DB info/i;

<<<<<<< HEAD
        $domain = $vm->search_domain($domain->name);
=======
        $domain = $vm->search_domain($dom_name);
>>>>>>> master
        eval {$domain->remove( $USER_ADMIN ) }  if $domain;
        if ( $@ && $@ =~ /No DB info/i ) {
            eval { $domain->domain->undefine() if $domain->domain };
        }

    }

    _remove_old_domains_kvm($vm)    if $vm->type =~ /qemu|kvm/i;
    _remove_old_domains_void($vm)    if $vm->type =~ /void/i;
}

sub _remove_old_domains_void {
    my $vm = shift;
    return _remove_old_domains_void_remote($vm) if !$vm->is_local;

    opendir my $dir, $vm->dir_img or return;
    while ( my $file = readdir($dir) ) {
        my $path = $vm->dir_img."/".$file;
        next if ! -f $path
            || $path !~ m{\.(yml|qcow|img)$};
        unlink $path or die "$! $path";
    }
    closedir $dir;
}

sub _remove_old_domains_void_remote($vm) {

    $vm->run_command("rm -f ".$vm->dir_img."/*yml "
                    .$vm->dir_img."/*qcow "
                    .$vm->dir_img."/*img"
    );
}

sub _remove_old_domains_kvm {
    my $vm = shift;

    if (!$vm) {
        eval {
            my $rvd_back = rvd_back();
            $vm = $rvd_back->search_vm('KVM');
        };
        diag($@) if $@;
        return if !$vm;
    }
    return if !$vm->vm;
    _activate_storage_pools($vm);

    my $base_name = base_domain_name();

    my @domains;
    eval { @domains = $vm->vm->list_all_domains() };
    return if $@ && $@ =~ /connect to host/;
    is($@,'') or return;

    for my $domain ( $vm->vm->list_all_domains ) {
        next if $domain->get_name !~ /^$base_name/;
        eval { 
            $domain->shutdown();
            sleep 1; 
            $domain->destroy() if $domain->is_active;
        }
            if $domain->is_active;
        warn "WARNING: error $@ trying to shutdown ".$domain->get_name if $@;

        $domain->managed_save_remove()
            if $domain->has_managed_save_image();

        eval { $domain->undefine };
        warn $@ if $@;
    }
}

sub remove_old_domains {
    _remove_old_domains_vm('KVM');
    _remove_old_domains_vm('Void');
    _remove_old_domains_kvm();
}

sub _activate_storage_pools($vm) {
    for my $sp ($vm->vm->list_all_storage_pools()) {
        next if $sp->is_active;
        diag("Activating sp ".$sp->get_name." on ".$vm->name);
        $sp->create();
    }
}
sub _remove_old_disks_kvm {
    my $vm = shift;

    my $name = base_domain_name();
    confess "Unknown base domain name " if !$name;

    if (!$vm) {
        my $rvd_back = rvd_back();
        $vm = $rvd_back->search_vm('KVM');
    }

    if (!$vm || !$vm->vm) {
        return;
    }
#    ok($vm,"I can't find a KVM virtual manager") or return;

    eval { $vm->refresh_storage_pools() };
    return if $@ && $@ =~ /Cannot recv data/;

    ok(!$@,"Expecting error = '' , got '".($@ or '')."'"
        ." after refresh storage pool") or return;
    for my $volume ( $vm->storage_pool->list_all_volumes()) {
        next if $volume->get_name !~ /^${name}_\d+.*\.(img|ro\.qcow2|qcow2)$/;
        $volume->delete;
    }
    $vm->storage_pool->refresh();
}
sub _remove_old_disks_void($node=undef){
    if (! defined $node || $node->is_local) {
       _remove_old_disks_void_local();
    } else {
       _remove_old_disks_void_remote($node);
    }
}

sub _remove_old_disks_void_remote($node) {
    confess "Remote node must be defined"   if !defined $node;
    my $cmd = "rm -rfv ".$node->dir_img."/".base_domain_name().'_*';
    $node->run_command($cmd);
}

sub _remove_old_disks_void_local {
    my $name = base_domain_name();

    my $dir_img =  $Ravada::Domain::Void::DIR_TMP ;
    opendir my $ls,$dir_img or return;
    while (my $file = readdir $ls ) {
        next if $file !~ /^${name}_\d/;

        my $disk = "$dir_img/$file";
        next if ! -f $disk;

        unlink $disk or die "I can't remove $disk";

    }
    closedir $ls;
}

sub remove_old_disks {
    _remove_old_disks_void();
    _remove_old_disks_kvm();
}

sub create_user {
    my ($name, $pass, $is_admin) = @_;

    Ravada::Auth::SQL::add_user(name => $name, password => $pass, is_admin => $is_admin);

    my $user;
    eval {
        $user = Ravada::Auth::SQL->new(name => $name, password => $pass);
    };
    die $@ if !$user;
    return $user;
}

sub wait_request {
    my $req = shift;
    for my $cnt ( 0 .. 10 ) {
        diag("Request ".$req->id." ".$req->command." ".$req->status." ".localtime(time))
            if $cnt > 2;
        last if $req->status eq 'done';
        sleep 2;
    }

}

sub init_vm {
    my $vm = shift;
    return if $vm->type =~ /void/i;
    _qemu_storage_pool($vm) if $vm->type =~ /qemu/i;
}

sub _exists_storage_pool {
    my ($vm, $pool_name) = @_;
    for my $pool ($vm->vm->list_storage_pools) {
        return 1 if $pool->get_name eq $pool_name;
    }
    return;
}

sub _qemu_storage_pool {
    my $vm = shift;

    my $pool_name = new_pool_name();

    if ( _exists_storage_pool($vm, $pool_name)) {
        $vm->default_storage_pool_name($pool_name);
        return;
    }

    my $uuid = Ravada::VM::KVM::_new_uuid('68663afc-aaf4-4f1f-9fff-93684c260942');

    my $dir = "/var/tmp/$pool_name";
    mkdir $dir if ! -e $dir;

    my $xml =
"<pool type='dir'>
  <name>$pool_name</name>
  <uuid>$uuid</uuid>
  <capacity unit='bytes'></capacity>
  <allocation unit='bytes'></allocation>
  <available unit='bytes'></available>
  <source>
  </source>
  <target>
    <path>$dir</path>
    <permissions>
      <mode>0711</mode>
      <owner>0</owner>
      <group>0</group>
    </permissions>
  </target>
</pool>"
;
    my $pool;
    eval { $pool = $vm->vm->create_storage_pool($xml) };
    ok(!$@,"Expecting \$@='', got '".($@ or '')."'") or return;
    ok($pool,"Expecting a pool , got ".($pool or ''));

    $vm->default_storage_pool_name($pool_name);
}

sub remove_qemu_pools {
    my $vm = rvd_back->search_vm('kvm') or return;

    for my $pool  ( $vm->vm->list_all_storage_pools) {
        next if $pool->get_name !~ /^test_/;
        diag("Removing ".$pool->get_name." storage_pool");
        $pool->destroy();
        eval { $pool->undefine() };
        warn $@ if$@;
        ok(!$@ or $@ =~ /Storage pool not found/i);
    }

}

sub remove_old_pools {
    remove_qemu_pools();
}

sub clean {
    my $file_remote_config = shift;
    remove_old_domains();
    remove_old_disks();
    remove_old_pools();


    if ($file_remote_config) {
        my $config;
        eval { $config = LoadFile($file_remote_config) };
        warn $@ if $@;
        _clean_remote_nodes($config)    if $config;
    }
    _clean_db();
}

sub _clean_db {
    my $sth = $CONNECTOR->dbh->prepare(
        "DELETE FROM vms "
    );
    $sth->execute;
    $sth->finish;

    $sth = $CONNECTOR->dbh->prepare(
        "DELETE FROM domains"
    );
    $sth->execute;
    $sth->finish;

}

sub clean_remote {
    return if ! -e $FILE_CONFIG_REMOTE;

    my $conf;
    eval { $conf = LoadFile($FILE_CONFIG_REMOTE) };
    return if !$conf;
    for my $vm_name (keys %$conf) {
        my $vm;
        eval { $vm = rvd_back->search_vm($vm_name) };
        warn $@ if $@;
        next if !$vm;

        my $node;
        eval { $node = $vm->new(%{$conf->{$vm_name}}) };
        next if ! $node;
        if ( !$node->is_active ) {
            $node->remove;
            next;
        }

        clean_remote_node($node);
        _remove_old_domains_vm($node);
        _remove_old_disks_kvm($node) if $vm_name =~ /^kvm/i;
        $node->remove();
    }
}

sub _clean_remote_nodes {
    my $config = shift;
    for my $name (keys %$config) {
        diag("Cleaning $name");
        my $node;
        my $vm = rvd_back->search_vm($config->{$name}->{type});
        eval { $node = $vm->new($config->{$name}) };
        warn $@ if $@;
        next if !$node || !$node->is_active;

        clean_remote_node($node);

    }
}

sub clean_remote_node {
    my $node = shift;

    _remove_old_domains_vm($node);
    _remove_old_disks($node);
    _flush_rules_remote($node)  if !$node->is_local();
}

sub _remove_old_disks {
    my $node = shift;
    if ( $node->type eq 'KVM' ) {
        _remove_old_disks_kvm($node);
    }elsif ($node->type eq 'Void') {
        _remove_old_disks_void($node);
    }   else {
        die "I don't know how to remove ".$node->type." disks";
    }
}

sub search_id_iso {
    my $name = shift;
    my $sth = $CONNECTOR->dbh->prepare("SELECT id FROM iso_images "
        ." WHERE name like ?"
    );
    $sth->execute("$name%");
    my ($id) = $sth->fetchrow;
    die "There is no iso called $name%" if !$id;
    return $id;
}

sub search_iptable_remote {
    my %args = @_;
    my $node = delete $args{node};
    if ($REX_ERROR ) {
        diag("Skipping search_iptable_remote , no Rex installed");
        return;
    }
    return if ! $node->_connect_rex();
    my $remote_ip = delete $args{remote_ip};
    my $local_ip = delete $args{local_ip};
    my $local_port= delete $args{local_port};
    my $jump = (delete $args{jump} or 'ACCEPT');
    my $iptables = iptables_list();

    $remote_ip .= "/32" if defined $remote_ip && $remote_ip !~ m{/};
    $local_ip .= "/32"  if defined $local_ip && $local_ip !~ m{/};

    my @found;

    my $count = 0;
    for my $line (@{$iptables->{filter}}) {
        my %args = @$line;
        next if $args{A} ne $CHAIN;
        $count++;
        if(exists $args{j} && defined $jump         && $args{j} eq $jump
           && exists $args{s} && defined $remote_ip && $args{s} eq $remote_ip
           && exists $args{d} && defined $local_ip  && $args{d} eq $local_ip
           && exists $args{dport} && defined $local_port && $args{dport} eq $local_port) {

            push @found,($count);
        }
    }
    return @found   if wantarray;
    return if !scalar@found;
    return $found[0];
}

sub _flush_rules_remote($node) {
    $node->run_command("iptables -F $CHAIN");
    $node->run_command("iptables -X $CHAIN");
}

sub flush_rules {
    my $ipt = open_ipt();
    $ipt->flush_chain('filter', $CHAIN);
    $ipt->delete_chain('filter', 'INPUT', $CHAIN);

    my @cmd = ('iptables','-t','nat','-F','PREROUTING');
    my ($in,$out,$err);
    run3(\@cmd, \$in, \$out, \$err);
    die $err if $err;
}

sub open_ipt {
    my %opts = (
    	'use_ipv6' => 0,         # can set to 1 to force ip6tables usage
	    'ipt_rules_file' => '',  # optional file path from
	                             # which to read iptables rules
	    'iptout'   => '/tmp/iptables.out',
	    'ipterr'   => '/tmp/iptables.err',
	    'debug'    => 0,
	    'verbose'  => 0,

	    ### advanced options
	    'ipt_alarm' => 5,  ### max seconds to wait for iptables execution.
	    'ipt_exec_style' => 'waitpid',  ### can be 'waitpid',
	                                    ### 'system', or 'popen'.
	    'ipt_exec_sleep' => 1, ### add in time delay between execution of
	                           ### iptables commands (default is 0).
	);

	my $ipt_obj = IPTables::ChainMgr->new(%opts)
    	or die "[*] Could not acquire IPTables::ChainMgr object";

}

sub _domain_node($node) {
    my $vm = rvd_back->search_vm('KVM','localhost');
    my $domain = $vm->search_domain($node->name);
    $domain = rvd_back->import_domain(name => $node->name
            ,user => user_admin->name
            ,vm => 'KVM'
            ,spinoff_disks => 0
    )   if !$domain || !$domain->is_known;

    ok($domain->id,"Expecting an ID for domain ".Dumper($domain)) or exit;
    $domain->_set_vm($vm, 'force');
    return $domain;
}

sub shutdown_node($node) {

    if ($node->is_active) {
        for my $domain ($node->list_domains()) {
            diag("Shutting down ".$domain->name." on node ".$node->name);
            $domain->shutdown_now(user_admin);
        }
    }
    $node->disconnect;

    my $domain_node = _domain_node($node);
    eval {
        $domain_node->shutdown(user => user_admin);# if !$domain_node->is_active;
    };
    sleep 2 if !$node->ping;

    my $max_wait = 30;
    for ( 1 .. $max_wait ) {
        diag("Waiting for node ".$node->name." to be inactive ...")  if !($_ % 10);
        last if !$node->ping;
        sleep 1;
    }
    return if !$node->ping;
    $node->run_command("init 0");
    for ( 1 .. $max_wait ) {
        diag("Waiting for node ".$node->name." to be inactive ...")  if !($_ % 10);
        last if !$node->ping;
        sleep 1;
    }

    is($node->ping,0);
}

sub start_node($node) {

    confess "Undefined node " if!$node;

    $node->disconnect;
    if ( $node->is_active ) {
        $node->connect && return;
        warn "I can't connect";
    }

    my $domain = _domain_node($node);

    ok($domain->_vm->host eq 'localhost');

    $domain->start(user => user_admin, remote_ip => '127.0.0.1')  if !$domain->is_active;

    sleep 2;

    $node->disconnect;
    sleep 1;

    for ( 1 .. 20 ) {
        last if $node->ping ;
        sleep 1;
        diag("Waiting for ping node ".$node->name." $_") if !($_ % 10);
    }

    is($node->ping,1,"Expecting ping node ".$node->name) or exit;

    for ( 1 .. 20 ) {
        last if $node->is_active;
        sleep 1;
        diag("Waiting for active node ".$node->name." $_") if !($_ % 10);
    }

    is($node->is_active,1,"Expecting active node ".$node->name) or exit;
    $node->connect;
}

sub remove_node($node) {
    shutdown_node($node);
    eval { $node->remove() };
    is(''.$@,'');

    my $node2;
    eval { $node2 = Ravada::VM->open($node->id) };
    like($@,qr"can't find VM");
    ok(!$node2, "Expecting no node ".$node->id);
}

sub shutdown_domain_internal($domain) {
    if ($domain->type eq 'KVM') {
        $domain->domain->destroy();
    } elsif ($domain->type eq 'Void') {
        $domain->_store(is_active => 0 );
    } else {
        confess "ERROR: I don't know how to shutdown internal domain of type ".$domain->type;
    }
}

sub start_domain_internal($domain) {
    if ($domain->type eq 'KVM') {
        $domain->domain->create();
    } elsif ($domain->type eq 'Void') {
        $domain->_store(is_active => 1 );
    } else {
        confess "ERROR: I don't know how to shutdown internal domain of type ".$domain->type;
    }
}


1;
