// Registers only the Web Awesome custom elements Atlas uses (ADR 0038, 0039), instead of the
// autoloader, so nothing beyond these six components is ever fetched.
import './components/button/button.js';
import './components/input/input.js';
import './components/textarea/textarea.js';
import './components/select/select.js';
import './components/option/option.js';
import './components/dialog/dialog.js';
