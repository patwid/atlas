// Registers only the Shoelace custom elements Atlas uses (ADR 0037), instead of the
// autoloader, so nothing beyond these five components is ever fetched.
import './components/button/button.js';
import './components/input/input.js';
import './components/textarea/textarea.js';
import './components/select/select.js';
import './components/option/option.js';
