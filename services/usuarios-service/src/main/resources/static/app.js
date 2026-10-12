'use strict';
const $ = id => document.getElementById(id);
let token = null, me = null, users = [], editing = null, resetting = null;
const roleNames = {ADMINISTRADOR:'Administrador',VENDEDOR:'Vendedor',BODEGUERO:'Bodeguero',CHOFER:'Chofer'};
function notice(text, error=false) { $('notice').textContent=text; $('notice').classList.toggle('error',error); }
async function api(path, method='GET', body) {
  let response;
  try { response=await fetch('/api'+path,{method,headers:{...(token?{Authorization:'Bearer '+token}:{}),...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})}); }
  catch { throw new Error('No se pudo conectar con el servicio. Intenta nuevamente.'); }
  const data=response.status===204?null:await response.json();
  if (!response.ok) {
    if (response.status===401 && token) signedOut();
    throw new Error(data.message+(data.errors?' · '+data.errors.join(' · '):''));
  }
  return data;
}
function show(panel) { for(const id of ['login-panel','password-panel','admin-panel']) $(id).hidden=id!==panel; }
function signedOut() { token=null;me=null;users=[];editing=null;resetting=null;$('identity').textContent='';$('logout').hidden=true;show('login-panel');$('users').replaceChildren();$('audit').replaceChildren();$('user-form').reset();if($('reset-dialog').open)$('reset-dialog').close(); }
function bindForm(id, work) { $(id).addEventListener('submit',async e=>{e.preventDefault();const button=e.submitter;button.disabled=true;notice('');try{await work(new FormData(e.target));}catch(error){notice(error.message,true);}finally{button.disabled=false;}}); }
bindForm('login-form',async f=>{
  const result=await api('/auth/login','POST',{identification:f.get('identification'),password:f.get('password')});
  token=result.accessToken;me=result.user;$('login-form').reset();
  if(!me.roles.includes('ADMINISTRADOR')){await api('/auth/logout','POST');signedOut();throw new Error('Este portal es exclusivo de administradores.');}
  $('identity').textContent=me.fullName+(me.master?' · Principal':' · Administrador');$('logout').hidden=false;
  if(me.mustChangePassword){$('password-description').textContent='Cambia tu contraseña temporal para continuar.';$('cancel-password').hidden=true;show('password-panel');}
  else {show('admin-panel');clearEditor();await refresh();}
});
bindForm('password-form',async f=>{
  if(f.get('newPassword')!==f.get('confirmation'))throw new Error('Las contraseñas nuevas no coinciden.');
  await api('/auth/password','POST',{currentPassword:f.get('currentPassword'),newPassword:f.get('newPassword')});
  $('password-form').reset();signedOut();notice('Contraseña actualizada. Ingresa con tu nueva contraseña.');
});
$('logout').onclick=async()=>{try{await api('/auth/logout','POST');signedOut();notice('Sesión cerrada.');}catch(e){notice(e.message,true);}};
$('change-password').onclick=()=>{$('password-description').textContent='Al cambiar tu contraseña se cerrarán todas tus sesiones.';$('cancel-password').hidden=false;show('password-panel');};
$('cancel-password').onclick=()=>{$('password-form').reset();show('admin-panel');};
function clearEditor(){editing=null;$('user-form').reset();$('editor-title').textContent='Nuevo usuario';$('user-form').elements.identification.disabled=false;$('temporary-label').hidden=false;$('user-form').elements.temporaryPassword.required=true;$('active-label').hidden=true;$('cancel-edit').hidden=true;roleControls();}
function roleControls(){const target=users.find(u=>u.id===editing);for(const box of $('user-form').querySelectorAll('[name=roles]'))box.disabled=(!me.master&&(box.value==='ADMINISTRADOR'||target?.roles.includes(box.value)))||(target?.master&&box.value==='ADMINISTRADOR');$('user-form').elements.active.disabled=!me.master||target?.master;$('permission-help').textContent=me.master?'Puedes delegar administración y retirar permisos.':'Puedes asignar roles operativos. El principal gestiona las retiradas de permisos y la delegación administrativa.';}
function edit(user){editing=user.id;const f=$('user-form');f.reset();f.elements.fullName.value=user.fullName;f.elements.identification.value=user.identification;f.elements.identification.disabled=true;f.elements.active.checked=user.active;for(const box of f.querySelectorAll('[name=roles]'))box.checked=user.roles.includes(box.value);$('editor-title').textContent='Editar usuario';$('temporary-label').hidden=true;f.elements.temporaryPassword.required=false;$('active-label').hidden=false;$('cancel-edit').hidden=false;roleControls();f.elements.fullName.focus();}
bindForm('user-form',async f=>{const roles=[...$('user-form').querySelectorAll('[name=roles]:checked')].map(box=>box.value);if(!roles.length)throw new Error('Selecciona al menos un rol.');const body={fullName:f.get('fullName'),roles};if(editing){body.active=$('user-form').elements.active.checked;await api('/admin/users/'+editing,'PUT',body);}else{body.identification=f.get('identification');body.temporaryPassword=f.get('temporaryPassword');await api('/admin/users','POST',body);}clearEditor();await refresh();notice('Usuario guardado.');});
$('cancel-edit').onclick=clearEditor;
function cell(row,text){const td=document.createElement('td');td.textContent=text;row.append(td);return td;}
function render(){const term=$('search').value.toLocaleLowerCase();$('users').replaceChildren();for(const u of users.filter(u=>(u.fullName+' '+u.identification).toLocaleLowerCase().includes(term))){const row=document.createElement('tr');const name=cell(row,u.fullName);const small=document.createElement('small');small.textContent=u.identification+(u.master?' · Principal':'');name.append(small);const roles=cell(row,'');for(const role of u.roles){const span=document.createElement('span');span.className='pill';span.textContent=roleNames[role];roles.append(span);}cell(row,u.active?(u.mustChangePassword?'Cambio de clave pendiente':'Activo'):'Inactivo');const actions=cell(row,'');if(me.master||!u.roles.includes('ADMINISTRADOR')){const button=document.createElement('button');button.textContent='Editar';button.onclick=()=>edit(u);actions.append(button);}if(me.master&&u.active){const button=document.createElement('button');button.textContent='Restablecer clave';button.onclick=()=>{resetting=u.id;$('reset-form').reset();$('reset-dialog').showModal();};actions.append(button);}$('users').append(row);}if(!$('users').children.length){const row=document.createElement('tr');cell(row,'No hay usuarios que coincidan.').colSpan=4;$('users').append(row);}}
async function audit(){if(!me.master)return;const events=await api('/admin/audit');$('audit').replaceChildren();for(const event of events){const row=document.createElement('tr');for(const value of [new Date(event.occurred_at).toLocaleString('es-EC'),event.actor,event.target,event.action,event.detail])cell(row,value);$('audit').append(row);}}
async function refresh(){users=await api('/admin/users');render();$('audit-panel').hidden=!me.master;await audit();}
for(const [id,work] of [['refresh',refresh],['audit-refresh',audit]])$(id).onclick=async()=>{try{await work();}catch(e){notice(e.message,true);}};
$('search').oninput=render;
bindForm('reset-form',async f=>{await api('/admin/users/'+resetting+'/password','POST',{temporaryPassword:f.get('temporaryPassword')});$('reset-form').reset();$('reset-dialog').close();if(resetting===me.id){signedOut();notice('Contraseña restablecida. Ingresa con la temporal.');}else{await refresh();notice('Contraseña temporal restablecida.');}});
$('cancel-reset').onclick=()=>{$('reset-form').reset();$('reset-dialog').close();};
