use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

my $BACKEND = 'KVM';

use_ok('Ravada');
use_ok("Ravada::Domain::$BACKEND");

my $test = Test::SQL::Data->new( config => 't/etc/sql.conf');

my @rvd_args = (
       config => 't/etc/ravada.conf' 
   ,connector => $test->connector 
);

my $RAVADA;
eval { $RAVADA = Ravada->new( @rvd_args ) };

my $CONT= 0;

sub test_vm_kvm {
    my $vm = $RAVADA->search_vm('kvm');
    ok($vm,"No vm found") or exit;
    ok(ref($vm) =~ /KVM$/,"vm is no kvm ".ref($vm)) or exit;

    ok($vm->type, "Not defined $vm->type") or exit;
    ok($vm->host, "Not defined $vm->host") or exit;

}
sub test_remove_domain {
    my $name = shift;

    my $domain;
    $domain = $RAVADA->search_domain($name,1);

    if ($domain) {
        diag("Removing domain $name");
        $domain->remove();
    }
    $domain = $RAVADA->search_domain($name);
    die "I can't remove old domain $name"
        if $domain;

    ok(!search_domain_db($name),"Domain $name still in db");
}

sub test_remove_domain_by_name {
    my $name = shift;

    diag("Removing domain $name");
    $RAVADA->remove_domain($name);

    my $domain = $RAVADA->search_domain($name, 1);
    die "I can't remove old domain $name"
        if $domain;

}

sub search_domain_db
 {
    my $name = shift;
    my $sth = $test->dbh->prepare("SELECT * FROM domains WHERE name=? ");
    $sth->execute($name);
    my $row =  $sth->fetchrow_hashref;
    return $row;

}

sub test_new_domain {
    my $active = shift;

    my ($name) = $0 =~ m{.*/(.*)\.t};
    $name .= "_".$CONT++;

    test_remove_domain($name);

    diag("Creating domain $name");
    my $domain = $RAVADA->create_domain(name => $name, id_iso => 1, active => $active
        , id_owner => 1
        , vm => $BACKEND
    );

    ok($domain,"Domain not created");
    my $exp_ref= 'Ravada::Domain::KVM';
    ok(ref $domain eq $exp_ref, "Expecting $exp_ref , got ".ref($domain))
        if $domain;

    my @cmd = ('virsh','desc',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    ok(!$?,"@cmd \$?=$? , it should be 0 $err $out");

    my $row =  search_domain_db($domain->name);
    ok($row->{name} && $row->{name} eq $domain->name,"I can't find the domain at the db");

    my $domain2 = $RAVADA->search_domain($domain->name);
    ok($domain2->id eq $domain->id,"Expecting id = ".$domain->id." , got ".$domain2->id);
    ok($domain2->name eq $domain->name,"Expecting name = ".$domain->name." , got "
        .$domain2->name);

    return $domain;
}

sub test_prepare_base {
    my $domain = shift;
    $domain->prepare_base();

    my $sth = $test->dbh->prepare("SELECT is_base FROM domains WHERE name=? ");
    $sth->execute($domain->name);
    my ($is_base) =  $sth->fetchrow;
    ok($is_base
            ,"Expecting is_base=1 got "
            .(${is_base} or '<UNDEF>'));
    $sth->finish;
}


sub test_domain_inactive {
    my $domain = test_domain(0);
}

sub test_domain{

    my $active = shift;
    $active = 1 if !defined $active;

    my $vm = $RAVADA->search_vm('kvm');
    my $n_domains = scalar $vm->list_domains();
    my $domain = test_new_domain($active);

    if (ok($domain,"test domain not created")) {
        my @list = $vm->list_domains();
        ok(scalar(@list) == $n_domains + 1,"Found ".scalar(@list)." domains, expecting "
            .($n_domains+1)
            ." "
            .join(" * ", sort map { $_->name } @list)
        );
        ok(!$domain->is_base,"Domain shouldn't be base "
            .Dumper($domain->_select_domain_db()));

        # test list domains
        my @list_domains = $vm->list_domains();
        ok(@list_domains,"No domains in list");
        my $list_domains_data = $RAVADA->list_domains_data();
        ok($list_domains_data && $list_domains_data->[0],"No list domains data ".Dumper($list_domains_data));
        my $is_base = $list_domains_data->[0]->{is_base} if $list_domains_data;
        ok($is_base eq '0',"Mangled is base '$is_base', it should be 0 "
            .Dumper($list_domains_data));

        # test prepare base
        test_prepare_base($domain);
        ok($domain->is_base,"Domain should be base"
            .Dumper($domain->_select_domain_db())

        );
        ok(!$domain->is_active,"domain should be inactive") if defined $active && $active==0;
        ok($domain->is_active,"domain should active") if defined $active && $active==1;

        ok(test_domain_in_virsh($domain->name,$domain->name)," not in virsh list all");
        my $domain2;
        eval { $domain2 = $vm->vm->get_domain_by_name($domain->name)};
        ok($domain2,"Domain ".$domain->name." missing in VM") or exit;

        test_remove_domain($domain->name);
    }
}

sub test_domain_in_virsh {
    my $name = shift;
    my $vm = $RAVADA->search_vm('kvm');

    for my $domain ($vm->vm->list_all_domains) {
        return 1 if $domain->get_name eq $name;
    }
    return 0;
}

sub test_domain_missing_in_db {
    # test when a domain is in the VM but not in the DB

    my $active = shift;
    $active = 1 if !defined $active;

    my $n_domains = scalar $RAVADA->list_domains();
    my $domain = test_new_domain($active);
    ok($RAVADA->list_domains > $n_domains,"There should be more than $n_domains");

    if (ok($domain,"test domain not created")) {

        my $sth = $test->connector->dbh->prepare("DELETE FROM domains WHERE id=?");
        $sth->execute($domain->id);

        my $domain2 = $RAVADA->search_domain($domain->name);
        ok(!$domain2,"This domain should not show up in Ravada, it's not in the DB");

        my $vm = $RAVADA->search_vm('kvm');
        my $domain3;
        eval { $domain3 = $vm->vm->get_domain_by_name($domain->name)};
        ok($domain3,"I can't find the domain in the VM") or return;

        my @list_domains = $RAVADA->list_domains;
        ok($RAVADA->list_domains == $n_domains,"There should be only $n_domains domains "
                                        .", there are ".scalar(@list_domains));

        test_remove_domain($domain->name);
    }
}


sub test_domain_by_name {
    my $domain = test_new_domain();

    if (ok($domain,"test domain not created")) {
        test_remove_domain_by_name($domain->name);
    }
}

sub test_prepare_import {
    my $domain = test_new_domain();

    if (ok($domain,"test domain not created")) {

        test_prepare_base($domain);
        ok($domain->is_base,"Domain should be base"
            .Dumper($domain->_select_domain_db())

        );

        test_remove_domain($domain->name);
    }

}

sub remove_old_domains {
    my ($name) = $0 =~ m{.*/(.*)\.t};
    for ( 0 .. 10 ) {
        my $dom_name = $name."_$_";
        my $domain = $RAVADA->search_domain($dom_name);
        $domain->shutdown_now() if $domain;
        test_remove_domain($dom_name);
    }
}

sub remove_old_disks {
    my ($name) = $0 =~ m{.*/(.*)\.t};

    my $vm = $RAVADA->search_vm('kvm');
    ok($vm,"I can't find a KVM virtual manager") or return;

    my $dir_img = $vm->dir_img();
    ok($dir_img," I cant find a dir_img in the KVM virtual manager") or return;

    for my $count ( 0 .. 10 ) {
        my $disk = $dir_img."/$name"."_$count.img";
        if ( -e $disk ) {
            unlink $disk or die "I can't remove $disk";
        }
    }
    $vm->storage_pool->refresh();
}

################################################################

my $vm;

eval { $vm = $RAVADA->search_vm('kvm') } if $RAVADA;
SKIP: {
    my $msg = "SKIPPED test: No KVM backend found";
    diag($msg)      if !$vm;
    skip $msg,10    if !$vm;

test_vm_kvm();

remove_old_domains();
remove_old_disks();
test_domain();
test_domain_missing_in_db();
test_domain_inactive();
test_domain_by_name();
test_prepare_import();

};
done_testing();
