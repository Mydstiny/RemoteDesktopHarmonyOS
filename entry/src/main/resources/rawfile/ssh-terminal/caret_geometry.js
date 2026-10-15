/* Original RemoteDesktop code. Uses xterm's public buffer and measured DOM geometry only. */
(function (root) {
  'use strict';
  function calculate(input) {
    var numbers = ['cursorX', 'cursorY', 'baseY', 'viewportY', 'cols', 'rows',
      'cellWidth', 'cellHeight', 'screenLeft', 'screenTop', 'width', 'height'];
    if (numbers.some(function (key) { return !Number.isFinite(input[key]); }) ||
        input.cols <= 0 || input.rows <= 0 || input.cellWidth <= 0 || input.cellHeight <= 0 ||
        input.width <= 0 || input.height <= 0) return null;
    var following = input.viewportY === input.baseY;
    var row = input.baseY + input.cursorY - input.viewportY;
    var offset = 0;
    if (following && !input.alternate && input.sparse && input.baseY === 0 &&
        input.cursorY >= 0 && input.cursorY < input.rows - 1) {
      offset = Math.max(0, Math.floor((input.rows - input.cursorY - 1) * input.cellHeight));
    }
    var bottom = input.screenTop + row * input.cellHeight + input.cellHeight;
    if (following && row >= 0 && row < input.rows && input.avoid) {
      var gap = Number.isFinite(input.gap) ? Math.max(8, Math.min(32, input.gap)) : 16;
      var safeBottom = Math.max(input.cellHeight, input.height - gap);
      if ((input.near && !input.alternate) || bottom + offset > safeBottom || bottom + offset - input.cellHeight < 0) {
        offset = safeBottom - bottom;
      }
      offset = Math.max(-input.height, Math.min(input.height, offset));
    }
    var x = input.screenLeft + Math.max(0, Math.min(input.cols - 1, input.cursorX)) * input.cellWidth;
    var y = input.screenTop + row * input.cellHeight + offset;
    return { x: x, y: y, width: Math.max(1, input.cellWidth), height: input.cellHeight,
      viewportWidth: input.width, viewportHeight: input.height, offset: Math.round(offset),
      visible: row >= 0 && row < input.rows && y < input.height && y + input.cellHeight > 0,
      followingBottom: following, alternateBuffer: input.alternate === true };
  }
  var api = { calculate: calculate };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.RemoteDeskTerminalCaretGeometry = api;
})(typeof window !== 'undefined' ? window : globalThis);
