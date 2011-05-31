// Module dependencies
var express = require('express'),
    app     = module.exports = express.createServer();


// Configuration
app.configure(function(){
  app.set('views', __dirname + '/views');
  app.set('view engine', 'jade');

  app.use(express.favicon());
  app.use(express.bodyParser());
  //app.use(express.logger({ format: ':status ":method :url"' }));
  
  var oneYear = 31556926000; // 1 year on milliseconds
  app.use(express.static(__dirname + '/public', { maxAge: oneYear }));
});


// Routes
app.get('/', function(req, res){
  res.render('index');
});

// Only listen on $ node app.js
if (!module.parent) {
  app.listen(10265);
  console.log("Listening on port %d", app.address().port);
}
