# Script to Setup Drupal Web Sites

Setup Drupal (8.x) web sites (on a clean Linux) automatically.

- Platform: Debian Linux 8.x/9.x, Nginx, MySQL, PHP
- Ref: [Setup/config a Drupal site (Chinese)](http://www.jianshu.com/p/cb6ee2a53de0)
- Ver: 0.2
- Updated: 10/15/2017
- Created: 6/10/2017
- Author: loblab

![Drupal site](https://raw.githubusercontent.com/loblab/drupal/master/screenshot1.png)

## Usage

1. Copy sample.conf, review/modify <your-config.conf>,
2. Run setup.sh <your-config>, 
3. You will see a URL with password finally. Open the URL in browser.

![Setup process](https://raw.githubusercontent.com/loblab/drupal/master/screenshot2.png)

## History

- 0.2 (10/14/2017) : Separates configurations to a config file
- 0.1 (6/10/2017) : Supports Drupal 8.x, Debian 8.x/9.x, Nginx

