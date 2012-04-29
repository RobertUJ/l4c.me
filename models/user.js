var Email, ObjectId, Schema, Url, encrypt_password, helpers, invoke, mongoose, mongooseTypes, user, validate_url;

mongoose = require('mongoose');

mongooseTypes = require('mongoose-types');

mongooseTypes.loadTypes(mongoose);

invoke = require('invoke');

helpers = require('../lib/helpers');

Schema = mongoose.Schema;

ObjectId = Schema.ObjectId;

Email = mongoose.SchemaTypes.Email;

Url = mongoose.SchemaTypes.Url;

encrypt_password = function(password) {
  return require('crypto').createHash('sha1').update(password + helpers.heart).digest('hex');
};

validate_url = function(v) {
  return /^(https?|ftp):\/\/(((([a-z]|\d|-|\.|_|~|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])|(%[\da-f]{2})|[!\$&'\(\)\*\+,;=]|:)*@)?(((\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.(\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.(\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.(\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5]))|((([a-z]|\d|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])|(([a-z]|\d|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])([a-z]|\d|-|\.|_|~|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])*([a-z]|\d|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])))\.)+(([a-z]|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])|(([a-z]|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])([a-z]|\d|-|\.|_|~|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])*([a-z]|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])))\.?)(:\d*)?)(\/((([a-z]|\d|-|\.|_|~|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])|(%[\da-f]{2})|[!\$&'\(\)\*\+,;=]|:|@)+(\/(([a-z]|\d|-|\.|_|~|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])|(%[\da-f]{2})|[!\$&'\(\)\*\+,;=]|:|@)*)*)?)?(\?((([a-z]|\d|-|\.|_|~|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])|(%[\da-f]{2})|[!\$&'\(\)\*\+,;=]|:|@)|[\uE000-\uF8FF]|\/|\?)*)?(\#((([a-z]|\d|-|\.|_|~|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])|(%[\da-f]{2})|[!\$&'\(\)\*\+,;=]|:|@)|\/|\?)*)?$/i.test(v);
};

user = new Schema({
  _photos: [
    {
      type: ObjectId,
      ref: 'photo'
    }
  ],
  clab: String,
  created_at: {
    "default": Date.now,
    type: Date
  },
  email: {
    lowercase: true,
    type: Email
  },
  facebook: {
    id: String,
    email: Email,
    username: String
  },
  password: {
    set: encrypt_password,
    type: String
  },
  random: {
    "default": Math.random,
    index: true,
    set: function(v) {
      return Math.random();
    },
    type: Number
  },
  twitter: {
    id: String,
    username: String
  },
  url: {
    type: String,
    validate: [validate_url, 'Please enter a valid URL']
  },
  username: {
    lowercase: true,
    type: String
  }
});

user.statics.encrypt_password = encrypt_password;

user.statics.login = function(username, password, next) {
  password = encrypt_password(password);
  return this.findOne({
    username: username,
    password: password
  }, function(err, doc) {
    if (err) return next(err, false);
    return next(null, doc);
  });
};

user.statics.serialize = function(user, next) {
  return next(null, user._id);
};

user.statics.deserialize = function(id, next) {
  return this.findOne({
    _id: id
  }, function(err, doc) {
    if (err || doc === null) return next(null, false);
    return next(null, doc);
  });
};

user.statics.facebook = function(token, tokenSecret, profile, next) {
  var model;
  model = this;
  return model.findOne({
    'facebook.id': profile.id
  }, function(err, doc) {
    if (!(err || doc === null)) return next(null, doc);
    return model.findOne({
      'email': profile._json.email
    }, function(err, doc) {
      var facebook, u, url;
      url = profile._json.website.split("\r\n")[0];
      facebook = {
        email: profile._json.email,
        id: profile.id,
        username: profile.username
      };
      if (doc) {
        doc.facebook = facebook;
        if (!doc.url && url) doc.url = url;
        doc.save();
        return next(null, doc);
      } else {
        u = new (mongoose.model('user'));
        u.email = facebook.email;
        u.facebook = facebook;
        if (url) u.url = url;
        u.username = profile.username;
        u.save();
        return next(null, u);
      }
    });
  });
};

user.statics.twitter = function(token, tokenSecret, profile, next) {
  var model;
  model = this;
  return model.findOne({
    'twitter.id': profile.id
  }, function(err, doc) {
    if (!(err || doc === null)) return next(null, doc);
    return model.findOne({
      'username': profile._json.screen_name
    }, function(err, doc) {
      var twitter, u, url;
      url = profile._json.url != null;
      twitter = {
        id: profile.id,
        username: profile._json.screen_name
      };
      if (doc) {
        doc.twitter = twitter;
        if (!doc.url && url) doc.url = url;
        doc.save();
        return next(null, doc);
      } else {
        u = new (mongoose.model('user'));
        u.twitter = twitter;
        u.username = twitter.username;
        if (url) u.url = url;
        u.save();
        return next(null, u);
      }
    });
  });
};

module.exports = mongoose.model('user', user);
