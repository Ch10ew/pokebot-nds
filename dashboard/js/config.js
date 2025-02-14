const configForm = document.getElementById('config-form');
const textAreas  = [...configForm.getElementsByTagName('textarea')].map(ele => ele.id);
const fields     = [...configForm.querySelectorAll('input, select')].map(ele => ele.id);
const checkboxes = [...configForm.querySelectorAll('input[type="checkbox"]')].map(ele => ele.id);

let config;
let loadedPrimoPhrases = false;

function sendConfig() {
    const sendConfigToClients = function() {
        try {
            for (var i = 0; i < textAreas.length; i++) {
                const key = textAreas[i]
                config[key] = jsyaml.load($('#' + key).val())
            }
        } catch (error) {
            return error
        }

        for (var i = 0; i < fields.length; i++) {
            const field = fields[i]
            config[field] = $('#' + field).val()
        }

        for (var i = 0; i < checkboxes.length; i++) {
            const field = checkboxes[i]
            config[field] = $('#' + field).prop('checked')
        }

        socketServerSend('config',
            {
                config: config,
                game: $('#editing').val()
            },
            function (error, _) {
                return error;
            }
        )
    }

    const error = sendConfigToClients()
    
    if (!error) {
        halfmoon.initStickyAlert({
            content: 'You may need to restart pokebot-nds.lua for the bot mode to update immediately. Other changes will take effect now.',
            title: 'Changes saved!',
            alertType: 'alert-success',
        })
    } else {
        halfmoon.initStickyAlert({
            content: error,
            title: 'Changes not saved',
            alertType: 'alert-danger',
        })
    }
}

/*  
    Updates the visibility of some fields that depend on others,
    so only the relevant settings are displayed when editing the config.
*/
function updateOptionVisibility() {
    $('#option_starters').hide();
    $('#option_moving_encounters').hide();
    $('#option_auto_catch').hide();
    $('#option_webhook').hide();
    $('#option_ping_user').hide();
    $("#option_encounter_milestones").hide();
    $('#option_primo').hide();
    $('#option_grotto').hide();
    $('#option_ot_override').hide();

    const mode = $('#mode').val();

    switch (mode) {
        case 'starters':
            $('#option_starters').show();
            break;
        case 'random_encounters':
            $('#option_moving_encounters').show();
            break;
        case 'random_encounters_small':
            $('#option_moving_encounters').show();
            break;
        case 'phenomenon_encounters':
            $('#option_moving_encounters').show();
            break;
        case 'hidden_grottos':
            $('#option_moving_encounters').show();
            $('#option_grotto').show();
            break;
        case 'primo_gift':
            $('#option_primo').show();

            if (!loadedPrimoPhrases) {
                $.getJSON("assets/en_easychat_iv.json", function (json) {
                    let phrases = '';
                    
                    json.forEach(word => {
                        phrases += `<option value=${word[0]}>${word[1]}</option>`;
                    });
                    
                    document.getElementById('primo1').innerHTML += phrases;
                    document.getElementById('primo2').innerHTML += phrases;
                    document.getElementById('primo3').innerHTML += phrases;
                    document.getElementById('primo4').innerHTML += phrases;

                    $('#primo1').val(config['primo1'])
                    $('#primo2').val(config['primo2'])
                    $('#primo3').val(config['primo3'])
                    $('#primo4').val(config['primo4'])
                });
                
                loadedPrimoPhrases = true;
            }
            break;
    }

    if ($('#auto_catch').prop('checked')) {
        $('#option_auto_catch').show();
    }

    if ($('#webhook_enabled').prop('checked')) {
        $('#option_webhook').show();
    }

    if ($('#ping_user').prop('checked')) {
        $('#option_ping_user').show();
    }

    if ($("#encounter_milestones_enable").prop("checked")) {
        $("#option_encounter_milestones").show();
    }

    if ($('#ot_override').prop('checked')) {
        $('#option_ot_override').show();
    }
}

function setEditableGames(clients) {
    const selected = $('#editing').val();

    $('#editing').empty()
    $('#editing').append('<option value="all">All Games</option>')

    for (var i = 0; i < clients.length; i++) {
        const name = clients[i].version;

        $('#editing').append('<option value="' + i.toString() + '">' + name + ' </option>')
    }

    $('#editing').val(selected);
}

function populateConfigForm() {
    for (var i = 0; i < textAreas.length; i++) {
        const key = textAreas[i]
        $('#' + key).val(jsyaml.dump(config[key]))
    }

    for (var i = 0; i < fields.length; i++) {
        const field = fields[i]
        $('#' + field).val(config[field])
    }

    for (var i = 0; i < checkboxes.length; i++) {
        const field = checkboxes[i]
        $('#' + field).prop('checked', config[field]);
    }

    $('#config-form').removeAttr('disabled')
    updateOptionVisibility()
}

function updateClientInfo() {
    socketServerGet('clients', (error, clients) => {
        if (error) {
            console.error(error);
            return;
        }
        
        const clientCount = clients.length;

        if (clientCount == 0) {
            clearInterval(elapsedInterval);
            elapsedStart = null;

            $('#elapsed-time').text('0s');
            $('#encounter-rate').text('0/h');
            return;
        }

        // Start elapsed timer if a game is connected
        if (!elapsedStart) {
            socketServerGet('elapsed_start', function (error, start) {
                if (error) {
                    console.error(error);
                    return;
                }

                elapsedStart = start;
                elapsedInterval = setInterval(updateStatBadges, 1000);

                updateStatBadges();
            });
        }

        setBadgeClientCount(clientCount);
        setEditableGames(clients)
    })
};

function testWebhook() {
    socketServerSend('test_webhook',
        {
            webhook_url: $('#webhook_url').val()
        },
        function (e, _) { });
}

// Hide values not relevant to the current bot mode
const form = document.querySelector('fieldset');
form.addEventListener('change', function () {
    updateOptionVisibility()
});

// Allow tab indentation in textareas
const textareas = document.getElementsByTagName('textarea');
const count = textareas.length;
for (var i = 0; i < count; i++) {
    textareas[i].onkeydown = function (e) {
        if (e.key == 'Tab') {
            e.preventDefault();
            var s = this.selectionStart;
            this.value = this.value.substring(0, this.selectionStart) + '  ' + this.value.substring(this.selectionEnd);
            this.selectionEnd = s + 2;
        }
    }
}

socketServerGet('config', function (error, data) {
    if (error) {
        console.error(error);
        return;
    }

    config = data;
    populateConfigForm();
});

// Ctrl + S shortcut
document.addEventListener('keydown', function (e) {
    if ((e.ctrlKey || e.metaKey) && e.key === 's') {
        e.preventDefault();
        sendConfig();
    }
});

updateClientInfo();

socketServerGet('config', function (error, config) {
    if (error) {
        console.error(error);
        return;
    }

    setInterval(() => {
        updateClientInfo();
    }, 1000);
})
