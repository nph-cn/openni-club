const brand = require('./utils/brand.generated');
App({globalData:{brand},onLaunch(){if(wx.setTabBarStyle)wx.setTabBarStyle({selectedColor:brand.primaryColor,color:'#626C78',backgroundColor:'#FFFFFF'});}});
