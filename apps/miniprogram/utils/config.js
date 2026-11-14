// Public configuration only. Never put merchant secrets, admin tokens or SMS secrets here.
const brand = require('./brand.generated');
module.exports = { apiBaseUrl: brand.apiBaseUrl || (brand.mode==='demo'?'http://localhost:8787/api/v1':''), mode: brand.mode, brand };
