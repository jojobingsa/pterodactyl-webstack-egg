<?php
$cfg['blowfish_secret'] = is_readable('/home/container/.pma-secret')
    ? trim(file_get_contents('/home/container/.pma-secret'))
    : 'change-this-persistent-secret-now!';

$i = 1;
$cfg['Servers'][$i]['auth_type'] = 'cookie';
$cfg['Servers'][$i]['host'] = '127.0.0.1';
$cfg['Servers'][$i]['port'] = '3306';
$cfg['Servers'][$i]['compress'] = false;
$cfg['Servers'][$i]['AllowNoPassword'] = false;
$cfg['TempDir'] = '/home/container/.cache/phpmyadmin';
$cfg['UploadDir'] = '';
$cfg['SaveDir'] = '';
