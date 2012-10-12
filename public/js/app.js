$(document).ready(function(){
    var upload_ready = false;
    var upload_data;
    var form_sent = false;
    $('form.upload').submit(function()
    {
        if (upload_ready)
        {
            return true;
        }

        $.ajax({
            url: '/register_upload',
            data: {filename: $('.fileinput').val()},
            dataType: 'json',
            success: function(response)
            {
                $('.share').html(response.download_link)
                upload_data = response;

                var interval = setInterval(function(){
                    $.ajax({
                        url: '/upload_status',
                        data: {transfer_id: upload_data.upload_id},
                        dataType: 'json',
                        success: function(r)
                        {
                            switch (r.status)
                            {
                                case "client.connected":
                                    if (!form_sent)
                                    {
                                        upload_ready = true;
                                        $('form.upload')[0].action = "/upload/?transfer_id=" + r.upload_id;

                                        $('form.upload')[0].submit();
                                        form_sent = true;
                                    }
                                    break;
                                case 'uploading':
                                    $('.progress .bar').css('width', Math.ceil(100 * r.bytes_uploaded/ r.bytes_total) + '%');
                                    break;
                                case 'finished':
                                    clearInterval(interval);
                                    break;
                            }
                        }
                    })
                }, 500)
            }
        });

        return false;
    })
})